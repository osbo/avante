//
//  AvanteDocument.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI
import Combine

// A simple container for the three metric scores.
struct AnalysisMetricsGroup: Codable, Equatable, Hashable {
    var novelty: Double
    var clarity: Double
    var flow: Double
}

// The new, flattened analysis object.
struct Analysis: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var range: CodableRange
    var metrics: AnalysisMetricsGroup
}

// The new top-level state for the entire document.
struct DocumentState: Codable, Equatable {
    var documentId: UUID = UUID()
    var fullText: String
    var analyses: [Analysis]
    var selectionRange: CodableRange?

    static func == (lhs: DocumentState, rhs: DocumentState) -> Bool {
        lhs.documentId == rhs.documentId && lhs.fullText == rhs.fullText
    }
}

struct CodableRange: Codable, Equatable, Hashable {
    let lowerBound: Int
    let upperBound: Int
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
            print("Successfully loaded document in new format: \(url.lastPathComponent)")
        } else {
            let initialText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            self.state = DocumentState(fullText: initialText, analyses: [], selectionRange: CodableRange(from: NSRange(location: 0, length: 0)))
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
            print("File saved successfully in new format to \(url.lastPathComponent)")
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
    
    public func clearAnalyses() {
        state.analyses.removeAll()
    }

    public func addAnalysis(_ newAnalysis: Analysis) {
        let newRange = NSRange(location: newAnalysis.range.lowerBound, length: newAnalysis.range.upperBound - newAnalysis.range.lowerBound)
        
        state.analyses.removeAll { existingAnalysis in
            let existingRange = NSRange(location: existingAnalysis.range.lowerBound, length: existingAnalysis.range.upperBound - existingAnalysis.range.lowerBound)
            return NSIntersectionRange(newRange, existingRange).length > 0
        }
        
        state.analyses.append(newAnalysis)
        state.analyses.sort { $0.range.lowerBound < $1.range.lowerBound }
    }
    
    public func adjustAnalysisRanges(for changeInLength: Int, at location: Int) {
        let delta = changeInLength
        guard delta != 0 else { return }

        let replacedLength = (delta > 0) ? 0 : abs(delta)
        let affectedRange = NSRange(location: location, length: replacedLength)

        var newAnalyses: [Analysis] = []
        for var analysis in state.analyses {
            let editRange = NSRange(location: analysis.range.lowerBound, length: analysis.range.upperBound - analysis.range.lowerBound)
            var shouldDiscard = false

            if NSMaxRange(editRange) <= location {
                // Case 1: Before the change. Keep it.
            } else if editRange.location >= NSMaxRange(affectedRange) {
                // Case 2: After the change. Shift it.
                analysis.range = CodableRange(
                    lowerBound: analysis.range.lowerBound + delta,
                    upperBound: analysis.range.upperBound + delta
                )
            } else {
                // Case 3: Overlaps. Discard it.
                shouldDiscard = true
            }

            if !shouldDiscard {
                newAnalyses.append(analysis)
            }
        }
        state.analyses = newAnalyses
    }
    
    public func updateSelectionState(to range: NSRange) {
        self.state.selectionRange = CodableRange(from: range)
    }
}
