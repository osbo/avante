//
//  AvanteDocument.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI
import Combine

struct DocumentState: Codable, Equatable {
    var documentId: UUID = UUID()
    var schemaVersion: String = "1.0.0"
    var fullText: String
    var analysisSessions: [AnalysisSession]
    var selectionRange: CodableRange?

    static func == (lhs: DocumentState, rhs: DocumentState) -> Bool {
        lhs.documentId == rhs.documentId
    }
}

struct AnalysisSession: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var startLocation: Int
    var contextSummary: String
    var analyzedEdits: [AnalyzedEdit]

    static func == (lhs: AnalysisSession, rhs: AnalysisSession) -> Bool {
        lhs.id == rhs.id
    }
}

struct AnalyzedEdit: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    // FIX: Add a timestamp to every analysis result.
    var timestamp: Date = Date()
    var range: CodableRange
    var text: String
    var analysisResult: AnalysisMetricsGroup
}

struct CodableRange: Codable, Equatable, Hashable {
    let lowerBound: Int
    let upperBound: Int
}

struct AnalysisMetricsGroup: Codable, Equatable, Hashable, Identifiable {
    var id: UUID = UUID()
    var novelty: Double
    var clarity: Double
    var flow: Double
}

class DocumentHistoryManager {
    private var history: [DocumentState] = []
    private var currentIndex: Int = -1
    private let maxHistorySize = 25 // Limit the number of undo steps

    var canUndo: Bool { currentIndex > 0 }
    var canRedo: Bool { currentIndex < history.count - 1 }
    var currentState: DocumentState? {
        history.indices.contains(currentIndex) ? history[currentIndex] : nil
    }

    func record(state: DocumentState) {
        // If we've undone, and are now making a new edit,
        // clear the old "future" history.
        if currentIndex < history.count - 1 {
            history.removeSubrange((currentIndex + 1)...)
        }

        history.append(state)

        // Trim the history if it exceeds the max size.
        if history.count > maxHistorySize {
            history.removeFirst()
        }
        
        currentIndex = history.count - 1
    }

    func undo() -> DocumentState? {
        guard canUndo else { return nil }
        currentIndex -= 1
        return currentState
    }

    func redo() -> DocumentState? {
        guard canRedo else { return nil }
        currentIndex += 1
        return currentState
    }

    func setInitialState(_ state: DocumentState) {
        history = [state]
        currentIndex = 0
    }
}


class AvanteDocument: ObservableObject {
    // MODIFIED: The state is now private(set) and we publish undo/redo availability.
    @Published private(set) var state: DocumentState
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false

    private(set) var url: URL
    private var historyManager = DocumentHistoryManager()
    
    init(url: URL) {
        self.url = url
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let data = try? Data(contentsOf: url),
            let decodedState = try? decoder.decode(DocumentState.self, from: data) {
            self.state = decodedState
            print("Successfully loaded document state from \(url.lastPathComponent)")
        } else {
            let initialText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            // REQUIRED: Ensure you are initializing the new selectionRange property here.
            self.state = DocumentState(fullText: initialText, analysisSessions: [], selectionRange: CodableRange(from: NSRange(location: 0, length: 0)))
            print("File is new or corrupt, creating new document state for: \(url.lastPathComponent)")
        }
        
        historyManager.setInitialState(self.state)
        updateUndoRedoState()
    }

    // MODIFIED: This method now simply encodes the *current* state.
    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            
            try data.write(to: url, options: .atomic)
            print("File saved successfully to \(url.lastPathComponent)")
        } catch {
            print("Failed to save file \(url.lastPathComponent). Error: \(error)")
        }
    }
    
    func updateURL(to newURL: URL) {
        self.url = newURL
    }

    // ADDED: A suite of methods to interact with the history manager.
    
    /// Records the current state of the document as a new snapshot in the undo history.
    func recordNewState() {
        // We use the document's `state` property which is updated by the AnalysisController.
        historyManager.record(state: self.state)
        updateUndoRedoState()
    }
    
    public func undo() -> DocumentState? {
        if let newState = historyManager.undo() {
            self.state = newState
            updateUndoRedoState()
            return self.state
        }
        return nil
    }

    public func redo() -> DocumentState? {
        if let newState = historyManager.redo() {
            self.state = newState
            updateUndoRedoState()
            return self.state
        }
        return nil
    }
    
    /// Updates the published boolean flags based on the history manager's state.
    private func updateUndoRedoState() {
        let newCanUndo = historyManager.canUndo
        if self.canUndo != newCanUndo {
            self.canUndo = newCanUndo
        }

        let newCanRedo = historyManager.canRedo
        if self.canRedo != newCanRedo {
            self.canRedo = newCanRedo
        }
    }
    
    /// Updates the document's full text content.
    public func updateFullText(to newText: String) {
        state.fullText = newText
    }

    /// Clears all analysis data from the document. Used for re-analysis.
    public func clearAnalysisSessions() {
        state.analysisSessions.removeAll()
    }

    /// Appends a new, empty analysis session.
    public func addNewAnalysisSession(_ session: AnalysisSession) {
        state.analysisSessions.append(session)
    }
    
    /// Adds a new analyzed edit to a specific session and resolves any range conflicts.
    public func addAnalyzedEdit(_ newEdit: AnalyzedEdit, toSessionWithID sessionID: UUID) {
        guard let sessionIndex = state.analysisSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        
        let newRange = NSRange(location: newEdit.range.lowerBound, length: newEdit.range.upperBound - newEdit.range.lowerBound)
        
        // Remove any old edits that conflict with the new one's range.
        state.analysisSessions[sessionIndex].analyzedEdits.removeAll { existingEdit in
            let existingRange = NSRange(location: existingEdit.range.lowerBound, length: existingEdit.range.upperBound - existingEdit.range.lowerBound)
            return NSIntersectionRange(newRange, existingRange).length > 0 || NSLocationInRange(newRange.location, existingRange)
        }
        
        // Add the new edit and re-sort.
        state.analysisSessions[sessionIndex].analyzedEdits.append(newEdit)
        state.analysisSessions[sessionIndex].analyzedEdits.sort { $0.range.lowerBound < $1.range.lowerBound }
    }
    
    /// Adjusts all stored analysis ranges in response to a text change.
    public func adjustAnalysisRanges(for changeInLength: Int, at location: Int) {
        let delta = changeInLength
        guard delta != 0 else { return }

        let replacedLength = (delta > 0) ? 0 : abs(delta)
        let affectedRange = NSRange(location: location, length: replacedLength)

        // Iterate through all sessions to update their edits.
        for sessionIndex in 0..<state.analysisSessions.count {
            var newEdits: [AnalyzedEdit] = []
            let originalEdits = state.analysisSessions[sessionIndex].analyzedEdits

            for var edit in originalEdits {
                let editRange = NSRange(location: edit.range.lowerBound, length: edit.range.upperBound - edit.range.lowerBound)
                var shouldDiscard = false

                if NSMaxRange(editRange) <= location {
                    // Case 1: Edit is BEFORE the change. Keep it.
                } else if editRange.location >= NSMaxRange(affectedRange) {
                    // Case 2: Edit is AFTER the change. Shift it.
                    edit.range = CodableRange(
                        lowerBound: edit.range.lowerBound + delta,
                        upperBound: edit.range.upperBound + delta
                    )
                } else {
                    // Case 3: Edit OVERLAPS with the change. Discard it.
                    shouldDiscard = true
                }

                if !shouldDiscard {
                    newEdits.append(edit)
                }
            }
            state.analysisSessions[sessionIndex].analyzedEdits = newEdits
        }
    }
    
    /// Resolves conflicts within each analysis session, keeping the most recent edits.
    public func performInitialConflictResolution() {
        self.state.analysisSessions = self.state.analysisSessions.map { session in
            let sortedEdits = session.analyzedEdits.sorted { $0.timestamp > $1.timestamp }
            var cleanedEdits: [AnalyzedEdit] = []
            
            for editToAdd in sortedEdits {
                let nsRangeToAdd = NSRange(location: editToAdd.range.lowerBound, length: editToAdd.range.upperBound - editToAdd.range.lowerBound)
                
                let hasConflict = cleanedEdits.contains { existingEdit in
                    let existingNSRange = NSRange(location: existingEdit.range.lowerBound, length: existingEdit.range.upperBound - existingEdit.range.lowerBound)
                    return NSIntersectionRange(nsRangeToAdd, existingNSRange).length > 0
                }
                
                if !hasConflict {
                    cleanedEdits.append(editToAdd)
                }
            }
            
            var cleanedSession = session
            cleanedSession.analyzedEdits = cleanedEdits.sorted { $0.range.lowerBound < $1.range.lowerBound }
            return cleanedSession
        }
    }
}
