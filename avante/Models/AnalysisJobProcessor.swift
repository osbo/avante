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

    // The completion handler now returns a Result type to communicate success or failure.
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
            // Using a defer block ensures these actions run whether the task succeeds or fails.
            defer {
                isProcessing = false
                // Check for more work that may have arrived during processing.
                processQueueIfNeeded(onResult: onResult)
            }
            
            do {
                let prompt = Prompt("Analyze the following text chunk: \"\(chunkToAnalyze)\"")
                let response = try await session.respond(to: prompt, generating: AnalysisMetricsResponse.self)
                
                let p = min(max(response.content.predictabilityScore, 0.0), 1.0)
                let c = min(max(response.content.clarityScore, 0.0), 1.0)
                let f = min(max(response.content.flowScore, 0.0), 1.0)
                
                let metrics = AnalysisMetricsGroup(predictability: p, clarity: c, flow: f)
                let result = AnalysisResult(metrics: metrics, rawResponse: response.content.description)

                // On success, send back the result and the edits that produced it.
                await onResult(.success(result), editsToProcess)
                
            } catch {
                // FIX: On failure, catch the error and send it back to the controller.
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
    @Guide(description: "A score from 0.0 (highly predictable) to 1.0 (highly original).")
    var predictabilityScore: Double
    
    @Guide(description: "A score from 0.0 (very confusing) to 1.0 (perfectly clear).")
    var clarityScore: Double
    
    @Guide(description: "A score from 0.0 (disjointed) to 1.0 (flows very well).")
    var flowScore: Double
    
    var description: String {
        "P: \(predictabilityScore), C: \(clarityScore), F: \(flowScore)"
    }
}
