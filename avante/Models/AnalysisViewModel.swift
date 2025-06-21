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
struct PredictabilityMetricResponse {
    @Guide(description: "A score from 0.0 (highly predictable) to 1.0 (highly original).")
    var predictabilityScore: Double
    
    @Guide(description: "A brief, one-sentence explanation for the score.")
    var justification: String
}


@MainActor
class AnalysisViewModel: ObservableObject {
    @Published var document: AvanteDocument
    @Published var highlightedRange: Range<String.Index>?
    @Published var isAnalyzing: Bool = false
    
    private var analysisTask: Task<Void, Never>?
    
    init(fileUrl: URL) {
        self.document = AvanteDocument(url: fileUrl)
    }
    
    func textDidChange() {
        analysisTask?.cancel()
        
        analysisTask = Task {
            let textToanalyze = document.file.text
            
            guard !Task.isCancelled else { return }
            
            await analyze(text: textToanalyze)
        }
    }
    
    private func analyze(text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        guard SystemLanguageModel.default.isAvailable else {
            print("Foundation Model is not available.")
            return
        }
        
        self.isAnalyzing = true
        defer { self.isAnalyzing = false }
        
        do {
            let instructions = Instructions("""
            You are a literary editor. Analyze the following text for predictability.
            Respond only with a PredictabilityMetricResponse object.
            """)
            let session = LanguageModelSession(instructions: instructions)
            
            let prompt = Prompt(text)
            let response = try await session.respond(to: prompt, generating: PredictabilityMetricResponse.self)
            
            let metricData = response.content
            
            let newMetric = AnalysisMetric(
                chunk: text,
                value: metricData.predictabilityScore,
                type: .predictability
            )
            
            document.file.analysis.append(newMetric)
            
        } catch {
            print("Error during analysis: \(error)")
        }
    }
    
    func highlight(metric: AnalysisMetric) {
        // For now, we'll highlight the entire text since we don't have range information
        self.highlightedRange = document.file.text.startIndex..<document.file.text.endIndex
    }
}
