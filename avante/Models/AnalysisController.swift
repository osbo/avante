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
    
    @Published private(set) var latestMetrics: AnalysisMetricsGroup?
    @Published private(set) var status: String = "Select a file to begin."

    private(set) var activeDocument: AvanteDocument?
    private(set) weak var workspace: WorkspaceViewModel?

    private let jobProcessor = AnalysisJobProcessor()
    private var currentAnalysisSessionID: UUID?

    func setWorkspace(_ workspace: WorkspaceViewModel) {
        self.workspace = workspace
    }

    func loadDocument(document: AvanteDocument?) {
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
        
        resetLiveSession()
    }

    func saveDocument() {
        guard let doc = activeDocument, let workspace = self.workspace else { return }

        // FIX: Tell the workspace we are about to perform a manual file operation.
        workspace.isPerformingManualFileOperation = true
        
        doc.state.fullText = self.documentText
        doc.save()
        workspace.markDocumentAsClean(url: doc.url)
        
        // After a short delay, allow file system events to be processed again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            workspace.isPerformingManualFileOperation = false
        }
    }
    
    func queueForAnalysis(edit: Edit) {
        if !edit.isLinear {
            createNewAnalysisSession(at: edit.range.location)
        }
        
        Task {
            self.status = "Word queued..."
            
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
        Task { await jobProcessor.reset() }
        
        Task {
            self.status = "Priming session..."
            let context = self.documentText
            
            do {
                let session = LanguageModelSession(instructions: Instructions.analysis)
                
                if !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let primingPrompt = Prompt("Here is the document's full context. Process it and prepare for incremental analysis prompts: \n---\n\(context)\n---")
                    _ = try await session.respond(to: primingPrompt)
                }
                
                if self.currentAnalysisSessionID == nil {
                    self.currentAnalysisSessionID = self.activeDocument?.state.analysisSessions.last?.id
                }
                
                await jobProcessor.set(session: session)
                
                self.status = "Ready."
                print("✅ Live session primed successfully.")
                
            } catch {
                self.status = "Failed to create session."
                print("❌ Error creating new session: \(error)")
            }
        }
    }
}

private extension Instructions {
    static let analysis = Instructions("""
    You are a writing analyst. For each text chunk, provide scores for Predictability, Clarity, and Flow from 0.0 to 1.0. Respond ONLY with the generable JSON for AnalysisMetricsGroup.
    """)
}
