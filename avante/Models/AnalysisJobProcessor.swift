//
//  AnalysisJobProcessor.swift
//  avante
//
//  Created by Carl Osborne on 6/24/25.
//

import Foundation
import FoundationModels

actor AnalysisJobProcessor {
    private var editQueue: [Edit] = []
    private var isProcessing = false
    private var activeSession: LanguageModelSession?

    func set(session: LanguageModelSession) {
        self.activeSession = session
        print("✅ AnalysisJobProcessor received new session.")
    }

    func reset() {
        self.editQueue.removeAll()
        self.isProcessing = false
        self.activeSession = nil
        print("⚙️ AnalysisJobProcessor has been reset.")
    }

    func queue(edit: Edit, onResult: @escaping @MainActor (Result<AnalysisResult, Error>, [Edit]) -> Void) {
        editQueue.append(edit)
        print("➡️ Queued word: '\(edit.textAdded)'. Current queue size: \(editQueue.count)")
        processQueueIfNeeded(onResult: onResult)
    }

    private func processQueueIfNeeded(onResult: @escaping @MainActor (Result<AnalysisResult, Error>, [Edit]) -> Void) {
        guard !isProcessing, !editQueue.isEmpty, let session = activeSession else {
            return
        }

        isProcessing = true
        
        let editsToProcess = editQueue
        editQueue.removeAll()
        
        let chunkToAnalyze = editsToProcess.map(\.textAdded).joined(separator: " ")
        
        guard !chunkToAnalyze.isEmpty else {
            isProcessing = false
            return
        }

        print("⚙️ Processing combined chunk: \"\(chunkToAnalyze)\"")

        Task {
            defer {
                isProcessing = false
                processQueueIfNeeded(onResult: onResult)
            }
            
            do {
                let prompt = Prompt("Analyze the following text chunk: \"\(chunkToAnalyze)\"")
                let response = try await session.respond(to: prompt, generating: AnalysisMetricsResponse.self)
                
                let content = response.content
                let n = min(max(content.noveltyScore, 0.0), 1.0)
                let c = min(max(content.clarityScore, 0.0), 1.0)
                let f = min(max(content.flowScore, 0.0), 1.0)
                
                let metrics = AnalysisMetricsGroup(novelty: n, clarity: c, flow: f)
                
                let descriptionString = "N: \(content.noveltyScore), C: \(content.clarityScore), F: \(content.flowScore)"
                let result = AnalysisResult(metrics: metrics, rawResponse: descriptionString)

                await onResult(.success(result), editsToProcess)
                
            } catch {
                print("❌ Actor processing failed: \(error)")
                await onResult(.failure(error), editsToProcess)
            }
        }
    }
}

struct AnalysisResult {
    let metrics: AnalysisMetricsGroup
    let rawResponse: String
}

@Generable
struct AnalysisMetricsResponse: CustomStringConvertible {
    @Guide(description: "A score from 0.00 (very predictable/cliche) to 1.00 (highly novel/original).")
    var noveltyScore: Double
    
    @Guide(description: "A score from 0.00 (very confusing) to 1.00 (perfectly clear).")
    var clarityScore: Double
    
    @Guide(description: "A score from 0.00 (disjointed) to 1.00 (flows very well).")
    var flowScore: Double
    
    var description: String {
        "N: \(noveltyScore), C: \(clarityScore), F: \(flowScore)"
    }
}
