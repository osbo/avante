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
            context.coordinator.isUpdatingFromModel = true
            
            let selectedRanges = textView.selectedRanges
            textView.string = self.text
            textView.selectedRanges = selectedRanges
            
            DispatchQueue.main.async {
                context.coordinator.isUpdatingFromModel = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, controller: analysisController)
    }

    class Coordinator: NSObject, NSTextStorageDelegate {
        var parent: AIAnalysisTextView
        var controller: AnalysisController
        weak var textView: NSTextView?
        
        private var wordBuffer: String = ""
        private let wordSeparators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        
        var isUpdatingFromModel = false
        
        init(_ parent: AIAnalysisTextView, controller: AnalysisController) {
            self.parent = parent
            self.controller = controller
        }
        
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            
            guard !isUpdatingFromModel else { return }
            guard editedMask.contains(.editedCharacters) else { return }
            
            // FIX: Update the binding synchronously to prevent the "eaten character" bug.
            // The didSet observer in AnalysisController will now handle setting the dirty flag.
            self.parent.text = textStorage.string
            
            if delta < 0 {
                flushWordBuffer(at: editedRange.location)
                return
            }
            
            let addedText = (textStorage.string as NSString).substring(with: editedRange)
            
            for character in addedText {
                if character.unicodeScalars.allSatisfy(wordSeparators.contains) {
                    flushWordBuffer(at: editedRange.location)
                } else {
                    wordBuffer.append(character)
                }
            }
        }
        
        private func flushWordBuffer(at separatorLocation: Int) {
            guard !wordBuffer.isEmpty else { return }
            
            let word = wordBuffer
            self.wordBuffer = ""

            let wordLocation = separatorLocation - word.count
            let wordRange = NSRange(location: wordLocation, length: word.count)
            
            guard wordLocation >= 0, let fullText = textView?.string else { return }
            guard NSMaxRange(wordRange) <= (fullText as NSString).length else { return }

            print("✅ Word complete: '\(word)'")
            
            let edit = Edit(
                textAdded: word,
                range: wordRange,
                isLinear: true,
                fullDocumentContext: fullText
            )
            
            controller.queueForAnalysis(edit: edit)
        }
    }
}
