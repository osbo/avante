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
    @Published var documentText: String = ""
    @Published private(set) var latestMetrics: AnalysisMetricsGroup?
    @Published private(set) var status: String = "Select a file to begin."

    private var document: AvanteDocument?
    private let jobProcessor = AnalysisJobProcessor()
    private var currentAnalysisSessionID: UUID?

    func loadDocument(from url: URL?) {
        // FIX: Check if the requested URL is already the one we have open.
        // If it is, do nothing to prevent accidental session resets from UI refreshes.
        if document?.url == url, document != nil {
            return
        }
        
        // If we proceed, it's a genuinely new document, so it's safe to reset.
        Task { await jobProcessor.reset() }
        
        guard let url = url else {
            self.document = nil
            self.documentText = ""
            self.latestMetrics = nil
            self.status = "Select a file to begin."
            currentAnalysisSessionID = nil
            return
        }
        
        let newDocument = AvanteDocument(url: url)
        self.document = newDocument
        self.documentText = newDocument.state.fullText
        self.status = "Document loaded."
        
        handleSessionBreak()
    }

    func saveDocument() {
        guard let document = document else { return }
        document.state.fullText = self.documentText
        document.save()
    }
    
    func queueForAnalysis(edit: Edit) {
        self.documentText = edit.fullDocumentContext
        
        if !edit.isLinear {
            handleSessionBreak(at: edit.range.location)
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
                       let sessionIndex = self.document?.state.analysisSessions.firstIndex(where: { $0.id == currentID }) {
                        self.document?.state.analysisSessions[sessionIndex].analyzedEdits.append(newAnalyzedEdit)
                    }
                
                case .failure(let error):
                    self.status = "Analysis failed."
                    if String(describing: error).contains("Context length") {
                        print("🚨 Context overflow detected! Automatically resetting session.")
                        self.handleSessionBreak(at: edit.range.location)
                    }
                }
            }
        }
    }
    
    private func handleSessionBreak(at location: Int? = nil) {
        print("SESSION BREAK: Starting new analysis session.")
        currentAnalysisSessionID = nil
        Task { await jobProcessor.reset() }
        
        Task {
            self.status = "Priming new session..."
            let context = self.documentText
            
            do {
                let session = LanguageModelSession(instructions: Instructions.analysis)
                
                if !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let primingPrompt = Prompt("Here is the document's full context. Process it and prepare for incremental analysis prompts: \n---\n\(context)\n---")
                    _ = try await session.respond(to: primingPrompt)
                }
                
                let newSession = AnalysisSession(startLocation: location ?? 0, contextSummary: "", analyzedEdits: [])
                self.document?.state.analysisSessions.append(newSession)
                self.currentAnalysisSessionID = newSession.id
                
                await jobProcessor.set(session: session)
                
                self.status = "Ready to analyze. Start typing."
                print("✅ New session primed successfully. Session ID: \(newSession.id)")
                
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
