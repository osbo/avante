//
//  Autocomplete.swift
//  avante
//
//  Created by Carl Osborne on 6/25/25.
//

import Foundation
import FoundationModels
import NaturalLanguage

@Generable
struct AutocompleteResponse {
    @Guide(description: "Whether the autocomplete was able to produce a valid completion. Set to true only if you can confidently predict the next few words.")
    var valid: Bool
    
    @Guide(description: "The predicted next few words (2-4 words) that would naturally follow the given text. Only provide this if valid is true.")
    var text: String
}

class Autocomplete {
    
    static func autocomplete(fullText: String, cursorPosition: Int, sentenceRanges: [NSRange], coordinator: AIAnalysisTextView.Coordinator, requestId: UUID) {
        let twoSentences = getTwoSentencesBeforeCursor(fullText: fullText, cursorPosition: cursorPosition, sentenceRanges: sentenceRanges)
        print("Two sentences before cursor: \(twoSentences)")
        
        // Send to foundation model for autocomplete prediction
        Task {
            do {
                let instructions = Instructions("You are an autocomplete tool. Given text, predict the next 2-4 words that would naturally follow. Only provide a prediction if you are confident it makes sense in context.")
                let session = LanguageModelSession(instructions: instructions)
                let prompt = Prompt(twoSentences)
                let response = try await session.respond(to: prompt, generating: AutocompleteResponse.self)
                
                let autocompleteResult = response.content
                print("Autocomplete valid: \(autocompleteResult.valid), text: \(autocompleteResult.text)")
                
                // Display the suggestion in the UI only if valid
                if autocompleteResult.valid {
                    await MainActor.run {
                        coordinator.displayAutocompleteSuggestion(autocompleteResult.text, at: cursorPosition, requestId: requestId)
                    }
                }
            } catch {
                // Don't show autocomplete for any errors, including guardrail violations
                if let generationError = error as? FoundationModels.LanguageModelSession.GenerationError {
                    print("Autocomplete blocked due to generation error: \(generationError)")
                }
                else {
                    print("Autocomplete error: \(error)")
                }
            }
        }
    }
    
    private static func getTwoSentencesBeforeCursor(fullText: String, cursorPosition: Int, sentenceRanges: [NSRange]) -> String {
        // Find sentences that contain or are before the cursor position
        let relevantSentences = sentenceRanges.filter { range in
            // Include sentences that end before or at the cursor, OR that contain the cursor
            range.upperBound <= cursorPosition || NSLocationInRange(cursorPosition, range)
        }
        
        // Get the last two relevant sentences
        let lastTwoSentences = relevantSentences.suffix(2)
        
        // Extract the text for these sentences, but truncate the last sentence at the cursor position
        let sentencesText = lastTwoSentences.enumerated().map { index, range in
            let sentenceText = (fullText as NSString).substring(with: range)
            
            // If this is the last sentence and it contains the cursor, truncate it
            if index == lastTwoSentences.count - 1 && NSLocationInRange(cursorPosition, range) {
                let relativePosition = cursorPosition - range.location
                return String(sentenceText.prefix(relativePosition))
            }
            
            return sentenceText
        }.joined(separator: " ")
        
        return sentencesText
    }
} 