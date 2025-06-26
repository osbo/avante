//
//  AnalysisController.swift
//  avante
//
//  Created by Carl Osborne on 6/24/25.
//

import Foundation
import SwiftUI
import FoundationModels
import Combine

struct Edit {
    let textAdded: String
    let range: NSRange
    let isLinear: Bool
    let fullDocumentContext: String
}

@MainActor
class AnalysisController: ObservableObject {
    @Published var documentText: String = "" {
        didSet {
            if activeDocument?.state.fullText != documentText {
                activeDocument?.state.fullText = documentText
                if let doc = activeDocument {
                    workspace?.markDocumentAsDirty(url: doc.url)
                }
            }
        }
    }
    
    @Published private(set) var activeHighlight: MetricType? = nil
    @Published private(set) var metricsForDisplay: AnalysisMetricsGroup?
    @Published private(set) var status: String = "Select a file to begin."

    let focusEditorSubject = PassthroughSubject<Void, Never>()

    private(set) var activeDocument: AvanteDocument?
    private(set) weak var workspace: WorkspaceViewModel?

    private let jobProcessor = AnalysisJobProcessor()
    private var currentAnalysisSessionID: UUID?
    private var sessionCreationTask: Task<Void, Error>?
    private var latestGeneratedMetrics: AnalysisMetricsGroup?

    func toggleHighlight(for metric: MetricType) {
        if activeHighlight == metric {
            activeHighlight = nil
        } else {
            activeHighlight = metric
        }
    }

    func setWorkspace(_ workspace: WorkspaceViewModel) {
        self.workspace = workspace
    }

    func loadDocument(document: AvanteDocument?) {
        activeHighlight = nil
        Task { await jobProcessor.clearQueue() }
        
        guard let doc = document else {
            self.activeDocument = nil
            self.documentText = ""
            self.metricsForDisplay = nil
            self.status = "Select a file to begin."
            return
        }

        if self.activeDocument?.url == doc.url { return }
        
        doc.state.analysisSessions = doc.state.analysisSessions.map { resolveConflicts(in: $0) }
        
        self.activeDocument = doc
        self.documentText = doc.state.fullText
        self.metricsForDisplay = doc.state.analysisSessions.flatMap { $0.analyzedEdits }.last?.analysisResult
        self.latestGeneratedMetrics = self.metricsForDisplay
        self.status = "Document loaded."
        
        createNewAnalysisSession()
    }

    func saveDocument() {
        guard let doc = activeDocument, let workspace = self.workspace else { return }
        
        workspace.isPerformingManualFileOperation = true
        doc.state.analysisSessions = doc.state.analysisSessions.map { resolveConflicts(in: $0) }
        doc.state.fullText = self.documentText
        doc.save()
        workspace.markDocumentAsClean(url: doc.url)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            workspace.isPerformingManualFileOperation = false
        }
    }
    
    func queueForAnalysis(edit: Edit) {
        if !edit.isLinear {
            createNewAnalysisSession(at: edit.range.location)
        }
        
        Task {
            _ = await sessionCreationTask?.result
            
            self.status = "Word queued..."
            
            await jobProcessor.queue(edit: edit) { result, processedEdits in
                switch result {
                case .success(let analysisResult):
                    self.latestGeneratedMetrics = analysisResult.metrics
                    self.metricsForDisplay = analysisResult.metrics
                    self.status = "Analysis complete."

                    guard let firstEdit = processedEdits.first, let lastEdit = processedEdits.last else { return }
                    let combinedRange = NSRange(location: firstEdit.range.location, length: NSMaxRange(lastEdit.range) - firstEdit.range.location)
                    let combinedText = processedEdits.map(\.textAdded).joined(separator: " ")

                    let newAnalyzedEdit = AnalyzedEdit(
                        range: CodableRange(from: combinedRange),
                        text: combinedText,
                        analysisResult: analysisResult.metrics
                    )
                    
                    self.resolveConflictsByAdding(newEdit: newAnalyzedEdit)
                
                case .failure(let error):
                    self.status = "Analysis failed."
                    if String(describing: error).contains("Context length") {
                        print("🚨 Context overflow detected! Resetting session.")
                        self.resetLiveSession()
                    }
                }
            }
        }
    }
    
    private func resolveConflictsByAdding(newEdit: AnalyzedEdit) {
        guard let currentID = self.currentAnalysisSessionID,
              let sessionIndex = self.activeDocument?.state.analysisSessions.firstIndex(where: { $0.id == currentID }) else { return }
        
        let newRange = NSRange(location: newEdit.range.lowerBound, length: newEdit.range.upperBound - newEdit.range.lowerBound)
        
        self.activeDocument?.state.analysisSessions[sessionIndex].analyzedEdits.removeAll { existingEdit in
            let existingRange = NSRange(location: existingEdit.range.lowerBound, length: existingEdit.range.upperBound - existingEdit.range.lowerBound)
            return NSIntersectionRange(newRange, existingRange).length > 0 || NSLocationInRange(newRange.location, existingRange)
        }
        
        self.activeDocument?.state.analysisSessions[sessionIndex].analyzedEdits.append(newEdit)
        self.activeDocument?.state.analysisSessions[sessionIndex].analyzedEdits.sort { $0.range.lowerBound < $1.range.lowerBound }
    }

    private func resolveConflicts(in session: AnalysisSession) -> AnalysisSession {
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
    
    func updateMetricsForCursor(at position: Int) {
        guard let allEdits = activeDocument?.state.analysisSessions.flatMap({ $0.analyzedEdits }), !allEdits.isEmpty else {
            metricsForDisplay = nil
            return
        }

        if let currentEdit = allEdits.first(where: { NSLocationInRange(position, NSRange(location: $0.range.lowerBound, length: $0.range.upperBound - $0.range.lowerBound)) }) {
            metricsForDisplay = currentEdit.analysisResult
        } else if let precedingEdit = allEdits.filter({ $0.range.upperBound <= position }).last {
            metricsForDisplay = precedingEdit.analysisResult
        } else {
            metricsForDisplay = latestGeneratedMetrics
        }
    }

    private func createNewAnalysisSession(at location: Int? = nil) {
        print("SESSION BREAK: Creating new analysis session in data model.")
        
        let newSession = AnalysisSession(startLocation: location ?? 0, contextSummary: "", analyzedEdits: [])
        self.activeDocument?.state.analysisSessions.append(newSession)
        self.currentAnalysisSessionID = newSession.id
        
        resetLiveSession()
    }
    
    private func resetLiveSession() {
        sessionCreationTask = Task {
            self.status = "Priming session..."
            
            await jobProcessor.resetSessionState()
            
            let context = self.documentText
            let instructions = Instructions(Prompting.analysisInstructions)
            let session = LanguageModelSession(instructions: instructions)
            
            if !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let primingPrompt = Prompt("Here is the document's full context. Process it and prepare for incremental analysis prompts: \n---\n\(context)\n---")
                _ = try await session.respond(to: primingPrompt)
            }
            
            if self.currentAnalysisSessionID == nil {
                self.currentAnalysisSessionID = self.activeDocument?.state.analysisSessions.last?.id
            }
            
            await jobProcessor.set(session: session)
            
            self.status = "Ready."
            print("✅ Live session primed and set successfully.")
            self.focusEditorSubject.send()
        }
    }
}

private enum Prompting {
    static let analysisInstructions = """
    You are a writing analyst. For each text chunk, provide scores for Novelty, Clarity, and Flow. Respond ONLY with the generable JSON for AnalysisMetricsResponse. Use a scale where 0.00 is the lowest/worst score and 1.00 is the highest/best.
    """
}

extension CodableRange {
    init(from nsRange: NSRange) {
        self.lowerBound = nsRange.location
        self.upperBound = NSMaxRange(nsRange)
    }
}
