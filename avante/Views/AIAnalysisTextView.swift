//
//  AIAnalysisTextView.swift
//  avante
//
//  Created by Carl Osborne on 6/24/25.
//

import SwiftUI
import AppKit

struct AIAnalysisTextView: NSViewRepresentable {
    @Binding var text: String
    var analysisController: AnalysisController

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        
        textView.font = .systemFont(ofSize: 16, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 20, height: 20)
        
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.textView = textView
        
        scrollView.documentView = textView
        
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != self.text {
            let selectedRanges = textView.selectedRanges
            textView.string = self.text
            textView.selectedRanges = selectedRanges
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, controller: analysisController)
    }

    class Coordinator: NSObject, NSTextStorageDelegate {
        var parent: AIAnalysisTextView
        var controller: AnalysisController
        weak var textView: NSTextView?
        
        // FIX: A buffer to build words character by character.
        private var wordBuffer: String = ""
        private let wordSeparators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        
        init(_ parent: AIAnalysisTextView, controller: AnalysisController) {
            self.parent = parent
            self.controller = controller
        }
        
        // This is now the core of the "producer" logic.
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            
            guard editedMask.contains(.editedCharacters) else { return }
            
            // Sync the full text back to the main state.
            DispatchQueue.main.async {
                self.parent.text = textStorage.string
            }
            
            // Deletions (backspace) are complex to handle perfectly with a buffer.
            // The safest and simplest strategy is to flush any pending word for analysis and reset.
            if delta < 0 {
                flushWordBuffer(at: editedRange.location)
                return
            }
            
            // Handle additions (typing or pasting).
            let addedText = (textStorage.string as NSString).substring(with: editedRange)
            
            for character in addedText {
                // Check if the typed character is a word separator (space, punctuation, etc.).
                if character.unicodeScalars.allSatisfy(wordSeparators.contains) {
                    // If it is, the word in the buffer is now "complete".
                    // The location of the separator is the end of our word.
                    flushWordBuffer(at: editedRange.location)
                } else {
                    // If it's a regular character, add it to the buffer.
                    wordBuffer.append(character)
                }
            }
        }
        
        // Helper function to send a completed word for analysis.
        private func flushWordBuffer(at separatorLocation: Int) {
            guard !wordBuffer.isEmpty else { return }
            
            let word = wordBuffer
            self.wordBuffer = "" // Clear the buffer immediately.

            // Calculate the range of the word that was just completed.
            let wordLocation = separatorLocation - word.count
            let wordRange = NSRange(location: wordLocation, length: word.count)
            
            // Ensure the calculated range is valid.
            guard wordLocation >= 0, let fullText = textView?.string else { return }
            guard NSMaxRange(wordRange) <= (fullText as NSString).length else { return }

            print("✅ Word complete: '\(word)'")
            
            // Create the Edit object for the completed word.
            let edit = Edit(
                textAdded: word,
                range: wordRange,
                isLinear: true, // Word-by-word typing is always linear in this model.
                fullDocumentContext: fullText
            )
            
            controller.queueForAnalysis(edit: edit)
        }
    }
}
