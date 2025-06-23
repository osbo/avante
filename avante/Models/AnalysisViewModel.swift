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
    
    init(fileUrl: URL) {
        self.document = AvanteDocument(url: fileUrl)
        initiateAnalysis(fullText: document.file.text)
    }
    
    func textDidChange(with newText: String) {
        initiateAnalysis(fullText: newText)
    }
    
    private func initiateAnalysis(fullText: String) {
        guard !isAnalyzing else {
            return
        }
        
        let lastAnalyzedOffset = document.file.analysis
            .filter { $0.predictability >= 0.0 } // Ignore skipped chunks
            .map(\.range.upperBound)
            .max() ?? 0
        
        guard lastAnalyzedOffset < fullText.count else {
            return
        }
        
        let startIndex = fullText.index(fullText.startIndex, offsetBy: lastAnalyzedOffset)
        let newTextToAnalyze = String(fullText[startIndex...])
        
        guard let lastWordBoundaryRange = newTextToAnalyze.range(of: "\\s", options: [.regularExpression, .backwards]) else {
            return
        }
        
        let chunkToAnalyze = String(newTextToAnalyze[..<lastWordBoundaryRange.lowerBound])
        
        guard !chunkToAnalyze.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let consumedLength = newTextToAnalyze.distance(from: newTextToAnalyze.startIndex, to: lastWordBoundaryRange.upperBound)
        
        let analysisRange = CodableRange(
            lowerBound: lastAnalyzedOffset,
            upperBound: lastAnalyzedOffset + consumedLength
        )

        Task {
            await MainActor.run { self.isAnalyzing = true }
            await analyze(chunk: chunkToAnalyze, for: analysisRange)
        }
    }
    
    private func analyze(chunk: String, for range: CodableRange) async {
        await MainActor.run {
            self.analysisError = nil
        }
        
        let result: (metrics: [AnalysisMetricsGroup]?, wasSkipped: Bool) = await Task.detached {
            do {
                let cleanChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanChunk.isEmpty else { return (nil, false) }
                
                let instructions = Instructions(/*...omitted for brevity...*/"""
                    You are a comprehensive writing analyst. Analyze the following text for three key metrics:
                    1. Predictability: How predictable or original the text is (0.0 = highly predictable, 1.0 = highly original)
                    2. Clarity: How clear and concise the text is (0.0 = very confusing, 1.0 = perfectly clear)
                    3. Flow: How well the text flows and its rhythm (0.0 = disjointed, 1.0 = flows very well)
                    
                    Respond ONLY with the AnalysisMetricsResponse object containing all three scores.
                    """)
                
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: Prompt(cleanChunk), generating: AnalysisMetricsResponse.self)
                
                let p = min(max(response.content.predictabilityScore, 0.0), 1.0)
                let c = min(max(response.content.clarityScore, 0.0), 1.0)
                let f = min(max(response.content.flowScore, 0.0), 1.0)
                
                return ([AnalysisMetricsGroup(range: range, predictability: p, clarity: c, flow: f)], false)

            // FIX: Replaced the 'catch where' with a standard 'catch' and an 'if case' inside.
            } catch let error as LanguageModelSession.GenerationError {
                // This is the correct way to handle specific cases of a thrown error.
                if case .guardrailViolation = error {
                    print("⚠️ Safety guardrail triggered for chunk '\(chunk)'. Skipping analysis for this chunk.")
                    return (metrics: nil, wasSkipped: true)
                }
                // Handle other generation errors if needed
                print("Error during analysis: \(error)")
                return (metrics: nil, wasSkipped: false)
            } catch {
                // Any other error is a hard failure.
                print("Error during analysis: \(error)")
                return (metrics: nil, wasSkipped: false)
            }
        }.value
        
        await MainActor.run {
            var shouldTriggerNextAnalysis = false

            if let newMetrics = result.metrics, !newMetrics.isEmpty {
                document.file.analysis.append(contentsOf: newMetrics)
                print("✅ Analysis completed. New offset: \(range.upperBound)")
                shouldTriggerNextAnalysis = true
            }
            
            if result.wasSkipped {
                let dummyMetric = AnalysisMetricsGroup(range: range, predictability: -1.0, clarity: -1.0, flow: -1.0)
                document.file.analysis.append(dummyMetric)
                print("⏭️ Skipped problematic chunk. New offset: \(range.upperBound)")
                shouldTriggerNextAnalysis = true
            }

            if result.metrics == nil && !result.wasSkipped {
                self.analysisError = "Analysis failed or returned no results."
                print("❌ Analysis failed or returned no results")
            }

            self.document.objectWillChange.send()
            self.isAnalyzing = false
            
            if shouldTriggerNextAnalysis {
                initiateAnalysis(fullText: self.document.file.text)
            }
        }
    }
}
