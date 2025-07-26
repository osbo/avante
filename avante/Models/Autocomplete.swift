//
//  Autocomplete.swift
//  avante
//
//  Created by Carl Osborne on 6/25/25.
//

import Foundation
import FoundationModels
import NaturalLanguage

class Autocomplete {
    
    static func autocomplete(fullText: String, cursorPosition: Int, sentenceRanges: [NSRange]) {
        let twoSentences = getTwoSentencesBeforeCursor(fullText: fullText, cursorPosition: cursorPosition, sentenceRanges: sentenceRanges)
        print("Two sentences before cursor: \(twoSentences)")
    }
    
    private static func getTwoSentencesBeforeCursor(fullText: String, cursorPosition: Int, sentenceRanges: [NSRange]) -> String {
        // Use the pre-computed sentence ranges from the existing tokenization
        let sentencesBeforeCursor = sentenceRanges.filter { $0.upperBound <= cursorPosition }
        
        // Get the last two sentences
        let lastTwoSentences = sentencesBeforeCursor.suffix(2)
        
        // Extract the text for these sentences
        let sentencesText = lastTwoSentences.map { range in
            (fullText as NSString).substring(with: range)
        }.joined(separator: " ")
        
        return sentencesText
    }
} 