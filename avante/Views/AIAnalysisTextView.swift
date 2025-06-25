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
    @ObservedObject var analysisController: AnalysisController

    func makeNSView(context: Context) -> NSScrollView {
        // 1. Create the standard AppKit views.
        let scrollView = NSScrollView()
        let textView = NSTextView()

        // 2. Configure the views' appearance and behavior.
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        
        textView.autoresizingMask = [.width, .height]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.font = .systemFont(ofSize: 16, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 20, height: 20)
        
        // Ensure the view is editable by default.
        textView.isEditable = true
        textView.isSelectable = true

        // 3. Get references to the default text system components.
        guard let textStorage = textView.textStorage,
              let originalLayoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            // This path should not be taken in a standard setup.
            return scrollView
        }
        
        // 4. Create our custom layout manager.
        let highlightingLayoutManager = HighlightingLayoutManager()
        
        // 5. FIX: Perform the complete, correct swap of the layout manager.
        textStorage.removeLayoutManager(originalLayoutManager)
        textStorage.addLayoutManager(highlightingLayoutManager)
        
        // Re-associate the existing text container with our new layout manager.
        // This was the missing step that broke the text system.
        highlightingLayoutManager.addTextContainer(textContainer)
        
        // 6. Connect the coordinator to the now-correct components.
        textStorage.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.layoutManager = highlightingLayoutManager

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView,
              let layoutManager = textView.layoutManager as? HighlightingLayoutManager else { return }

        if textView.string != self.text {
            context.coordinator.isUpdatingFromModel = true
            
            let selectedRanges = textView.selectedRanges
            textView.string = self.text
            textView.selectedRanges = selectedRanges
            
            DispatchQueue.main.async {
                context.coordinator.isUpdatingFromModel = false
            }
        }
        
        let allEdits = analysisController.activeDocument?.state.analysisSessions.flatMap { $0.analyzedEdits } ?? []
        layoutManager.analysisData = allEdits
        layoutManager.activeHighlight = analysisController.activeHighlight
        
        if let textContainer = textView.textContainer {
            let visibleRect = nsView.documentVisibleRect
            let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            layoutManager.invalidateDisplay(forGlyphRange: visibleGlyphRange)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, controller: analysisController)
    }

    class Coordinator: NSObject, NSTextStorageDelegate {
        var parent: AIAnalysisTextView
        var controller: AnalysisController
        weak var textView: NSTextView?
        weak var layoutManager: HighlightingLayoutManager?
        
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
