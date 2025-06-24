//
//  AnalysisViewModel.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI
import FoundationModels
import Combine

@Generable
struct AnalysisMetricsResponse {
    @Guide(description: "A score from 0.0 (highly predictable) to 1.0 (highly original).")
    var predictabilityScore: Double
    
    @Guide(description: "A score from 0.0 (very confusing) to 1.0 (perfectly clear).")
    var clarityScore: Double
    
    @Guide(description: "A score from 0.0 (disjointed) to 1.0 (flows very well).")
    var flowScore: Double
}

class AnalysisViewModel: ObservableObject {
    @Published var document: AvanteDocument
    @Published var highlightedRange: Range<String.Index>?
    @Published var isAnalyzing: Bool = false
    @Published var analysisError: String?
    
    @Published private(set) var isPriming: Bool = false
    private var session: LanguageModelSession?
    private var primingTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    
    init(fileUrl: URL) {
        self.document = AvanteDocument(url: fileUrl)
        primeSession()
    }
    
    func textDidChange(with newText: String) {
        initiateAnalysis(fullText: newText)
    }
    
    private func primeSession() {
        // Ensure we only prime once.
        guard primingTask == nil, session == nil else { return }
        
        print("🚀 Starting to prime session for \(document.url.lastPathComponent)...")
        self.isPriming = true
        
        primingTask = Task {
            let initialContext = document.file.text
            let instructions = Instructions("""
                You are a comprehensive writing analyst named Avante. Your purpose is to provide scores for Predictability, Clarity, and Flow on a scale of 0.0 to 1.0 for incoming text.

                You will be given an initial context of a developing document. After this, you will receive a series of short prompts with new text to be appended.

                For each new prompt, you must analyze the new text *as it fits into the complete, developing document* and respond ONLY with the scores in the required generable JSON format. You must remember each new piece of text to expand your understanding of the document's context.
                """)
            
            // Create the session that will be used for all future analyses for this document.
            self.session = LanguageModelSession(instructions: instructions)
            
            // If the document is empty, we don't need to send a priming prompt.
            guard !initialContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await MainActor.run {
                    print("✅ Session created for empty document. No priming needed.")
                    self.isPriming = false
                }
                return
            }

            do {
                // Send the priming prompt with the full initial text.
                let primingPrompt = Prompt("""
                    Here is the initial context of the document. Please process it and acknowledge your understanding by providing an overall analysis for the entire text provided.
                    ---
                    \(initialContext)
                    ---
                    """)
                let response = try await session!.respond(to: primingPrompt, generating: AnalysisMetricsResponse.self)
                let p = min(max(response.content.predictabilityScore, 0.0), 1.0)
                let c = min(max(response.content.clarityScore, 0.0), 1.0)
                let f = min(max(response.content.flowScore, 0.0), 1.0)
                let range = CodableRange(lowerBound: 0, upperBound: initialContext.count)
                let initialMetrics = AnalysisMetricsGroup(range: range, predictability: p, clarity: c, flow: f)
                
                await MainActor.run {
                    document.file.analysis = [initialMetrics] // Replace any old analysis
                    print("✅ Session primed successfully with initial context.")
                    self.isPriming = false
                }
            } catch {
                await MainActor.run {
                    self.analysisError = "Failed to prepare analysis session."
                    print("❌ Error during session priming: \(error)")
                    self.isPriming = false
                }
            }
        }
    }
    
    private func initiateAnalysis(fullText: String) {
        // Do not start analysis if the session isn't ready, or if another analysis is already running.
        guard !isPriming, session != nil, !isAnalyzing else { return }
        
        let lastAnalyzedOffset = document.file.analysis.map(\.range.upperBound).max() ?? 0
        guard lastAnalyzedOffset < fullText.count else { return }
        
        let startIndex = fullText.index(fullText.startIndex, offsetBy: lastAnalyzedOffset)
        let newTextToAnalyze = String(fullText[startIndex...])
        
        guard let lastWordBoundaryRange = newTextToAnalyze.range(of: "\\s", options: [.regularExpression, .backwards]) else { return }
        let chunkToAnalyze = String(newTextToAnalyze[..<lastWordBoundaryRange.lowerBound])
        guard !chunkToAnalyze.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let consumedLength = newTextToAnalyze.distance(from: newTextToAnalyze.startIndex, to: lastWordBoundaryRange.upperBound)
        let analysisRange = CodableRange(lowerBound: lastAnalyzedOffset, upperBound: lastAnalyzedOffset + consumedLength)

        self.isAnalyzing = true
        analysisTask = Task {
            await analyze(chunk: chunkToAnalyze, for: analysisRange)
        }
    }
    
    private func analyze(chunk: String, for range: CodableRange) async {
        guard let session = self.session else {
            await MainActor.run { self.isAnalyzing = false }
            return
        }
        
        let incrementalPrompt = Prompt("Analyze the following text in the context of our ongoing conversation: \"\(chunk)\"")
        
        do {
            let response = try await session.respond(to: incrementalPrompt, generating: AnalysisMetricsResponse.self)
            let p = min(max(response.content.predictabilityScore, 0.0), 1.0)
            let c = min(max(response.content.clarityScore, 0.0), 1.0)
            let f = min(max(response.content.flowScore, 0.0), 1.0)
            let newMetrics = AnalysisMetricsGroup(range: range, predictability: p, clarity: c, flow: f)
            
            await MainActor.run {
                document.addAnalysisMetrics([newMetrics])
                print("✅ Incremental analysis succeeded. New offset: \(range.upperBound)")
                self.isAnalyzing = false
            }
        } catch {
            await MainActor.run {
                self.analysisError = "Analysis failed."
                print("❌ Error during incremental analysis: \(error)")
                self.isAnalyzing = false
            }
        }
    }
}
