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
    @Published private(set) var latestMetrics: AnalysisMetricsGroup?
    @Published private(set) var status: String = "Select a file to begin."

    private(set) var activeDocument: AvanteDocument?
    private(set) weak var workspace: WorkspaceViewModel?

    private let jobProcessor = AnalysisJobProcessor()
    private var currentAnalysisSessionID: UUID?
    private var sessionCreationTask: Task<Void, Error>?

    func toggleHighlight(for metric: MetricType) {
        if activeHighlight == metric {
            activeHighlight = nil
        } else {
            activeHighlight = metric
        }
        print("Toggled highlight. Active: \(activeHighlight?.rawValue ?? "none")")
    }

    func setWorkspace(_ workspace: WorkspaceViewModel) {
        self.workspace = workspace
    }

    func loadDocument(document: AvanteDocument?) {
        activeHighlight = nil
        
        guard let doc = document else {
            self.activeDocument = nil
            self.documentText = ""
            self.latestMetrics = nil
            self.status = "Select a file to begin."
            return
        }

        if self.activeDocument?.url == doc.url { return }
        
        self.activeDocument = doc
        self.documentText = doc.state.fullText
        self.status = "Document loaded."
        
        createNewAnalysisSession()
    }

    func saveDocument() {
        guard let doc = activeDocument, let workspace = self.workspace else { return }
        
        workspace.isPerformingManualFileOperation = true
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
            // Await the session creation task to prevent a race condition on new files.
            _ = await sessionCreationTask?.result
            
            self.status = "Word queued..."
            
            // FIX: Call the correct `queue` method on the stateful actor.
            await jobProcessor.queue(edit: edit) { result, processedEdits in
                switch result {
                case .success(let analysisResult):
                    self.latestMetrics = analysisResult.metrics
                    self.status = "Analysis complete."

                    guard let firstEdit = processedEdits.first, let lastEdit = processedEdits.last else { return }
                    let combinedRange = NSRange(location: firstEdit.range.location, length: NSMaxRange(lastEdit.range) - firstEdit.range.location)
                    let combinedText = processedEdits.map(\.textAdded).joined(separator: " ")

                    let newAnalyzedEdit = AnalyzedEdit(
                        range: CodableRange(lowerBound: combinedRange.location, upperBound: NSMaxRange(combinedRange)),
                        text: combinedText,
                        analysisResult: analysisResult.metrics
                    )
                    
                    if let currentID = self.currentAnalysisSessionID,
                       let sessionIndex = self.activeDocument?.state.analysisSessions.firstIndex(where: { $0.id == currentID }) {
                        self.activeDocument?.state.analysisSessions[sessionIndex].analyzedEdits.append(newAnalyzedEdit)
                    }
                
                case .failure(let error):
                    self.status = "Analysis failed."
                    if String(describing: error).contains("Context length") {
                        print("🚨 Context overflow detected! Automatically resetting session.")
                        self.createNewAnalysisSession(at: edit.range.location)
                    }
                }
            }
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
            let context = self.documentText
            
            try await jobProcessor.reset()
            
            let instructions = Instructions(Prompting.analysisInstructions)
            let session = LanguageModelSession(instructions: instructions)
            
            if !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let primingPrompt = Prompt("Here is the document's full context. Process it and prepare for incremental analysis prompts: \n---\n\(context)\n---")
                _ = try await session.respond(to: primingPrompt)
            }
            
            if self.currentAnalysisSessionID == nil {
                self.currentAnalysisSessionID = self.activeDocument?.state.analysisSessions.last?.id
            }
            
            try await jobProcessor.set(session: session)
            
            self.status = "Ready."
            print("✅ Live session primed and set successfully.")
        }
    }
}

private enum Prompting {
    static let analysisInstructions = """
    You are a writing analyst. For each text chunk, provide scores for Novelty, Clarity, and Flow. Respond ONLY with the generable JSON for AnalysisMetricsResponse. Use a scale where 0.00 is the lowest/worst score and 1.00 is the highest/best.
    """
}
