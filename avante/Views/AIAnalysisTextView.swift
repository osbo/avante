//
//  AIAnalysisTextView.swift
//  avante
//
//  Created by Carl Osborne on 6/24/25.
//

import SwiftUI
import AppKit
import Combine

fileprivate extension String {
    func sentenceRange(for location: Int) -> NSRange {
        var sentenceRange = NSRange(location: location, length: 0)
        guard location <= self.count else { return sentenceRange }
        
        let targetIndex = self.index(self.startIndex, offsetBy: location, limitedBy: self.endIndex) ?? self.endIndex

        self.enumerateSubstrings(in: self.startIndex..<self.endIndex, options: [.bySentences, .localized]) { (substring, substringRange, enclosingRange, stop) in
            // Check if the cursor is within the sentence, or at the very end of it.
            if substringRange.contains(targetIndex) || (substringRange.upperBound == targetIndex && !substringRange.isEmpty) {
                sentenceRange = NSRange(substringRange, in: self)
                stop = true
            }
        }
        return sentenceRange
    }
}

// Custom NSTextView subclass to handle mouse events correctly
fileprivate class FocusAwareTextView: NSTextView {
    weak var analysisController: AnalysisController?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        self.trackingAreas.forEach { self.removeTrackingArea($0) }
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow]
        let trackingArea = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
        self.addTrackingArea(trackingArea)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        analysisController?.mouseDidMove()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        analysisController?.mouseDidExit()
    }
}


struct AIAnalysisTextView: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var analysisController: AnalysisController

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = FocusAwareTextView()
        
        textView.analysisController = context.coordinator.controller
        
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        
        textView.drawsBackground = false
        
        textView.autoresizingMask = [.width, .height]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.font = NSFont(name: "SF Pro Text", size: 16)
        // This sets the default color and ensures it adapts to the theme.
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.isEditable = true
        textView.isSelectable = true

        guard let textStorage = textView.textStorage,
              let originalLayoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return scrollView
        }
        
        let highlightingLayoutManager = HighlightingLayoutManager()
        textStorage.removeLayoutManager(originalLayoutManager)
        textStorage.addLayoutManager(highlightingLayoutManager)
        highlightingLayoutManager.addTextContainer(textContainer)
        
        textStorage.delegate = context.coordinator
        textView.delegate = context.coordinator
        
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
        
        context.coordinator.updateFocus(on: textView)
        
        if let textContainer = textView.textContainer {
            let visibleRect = nsView.documentVisibleRect
            let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            layoutManager.invalidateDisplay(forGlyphRange: visibleGlyphRange)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, controller: analysisController)
    }

    class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: AIAnalysisTextView
        var controller: AnalysisController
        weak var textView: NSTextView?
        weak var layoutManager: HighlightingLayoutManager?
        
        private var wordBuffer: String = ""
        private let wordSeparators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        var isUpdatingFromModel = false
        
        private var cancellables = Set<AnyCancellable>()
        
        init(parent: AIAnalysisTextView, controller: AnalysisController) {
            self.parent = parent
            self.controller = controller
            super.init()

            controller.focusEditorSubject
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    print("Received focus signal. Making text view first responder.")
                    self?.textView?.window?.makeFirstResponder(self?.textView)
                }
                .store(in: &cancellables)
        }
        
        // MARK: - Focus Mode Handling
        
        func updateFocus(on textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }

            let shouldDim = controller.isFocusModeEnabled &&
                            controller.isMouseStationary &&
                            controller.textViewSelectionRange.length == 0 &&
                            controller.activeHighlight == nil

            let fullRange = NSRange(location: 0, length: textStorage.length)
            
            // Get the correct, theme-aware default color from the text view itself.
            let defaultColor = NSColor.labelColor
            let dimmedColor = NSColor.tertiaryLabelColor

            let sentenceRange: NSRange
            if shouldDim {
                sentenceRange = textStorage.string.sentenceRange(for: controller.textViewSelectionRange.location)
            } else {
                sentenceRange = fullRange
            }
            
            // Directly apply attributes without animation for now.
            textStorage.beginEditing()
            
            // First, remove all custom foreground color attributes to reset to the view's default.
            textStorage.removeAttribute(.foregroundColor, range: fullRange)
            // Always set the entire range to .labelColor
            textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

            if shouldDim {
                // Only apply the dimmed color to the ranges outside the focused sentence.
                if sentenceRange.location > 0 {
                    let beforeRange = NSRange(location: 0, length: sentenceRange.location)
                    textStorage.addAttribute(.foregroundColor, value: dimmedColor, range: beforeRange)
                }
                let afterLocation = NSMaxRange(sentenceRange)
                if afterLocation < fullRange.length {
                    let afterRange = NSRange(location: afterLocation, length: fullRange.length - afterLocation)
                    textStorage.addAttribute(.foregroundColor, value: dimmedColor, range: afterRange)
                }
            }
            
            textStorage.endEditing()
        }

        // MARK: - Delegate Methods
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            controller.textViewSelectionRange = textView.selectedRange()
            
            let cursorPosition = textView.selectedRange().location
            controller.updateMetricsForCursor(at: cursorPosition)
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
            
            for (offset, character) in addedText.enumerated() {
                let characterLocation = editedRange.location + offset
                
                if character.unicodeScalars.allSatisfy(wordSeparators.contains) {
                    flushWordBuffer(at: characterLocation)
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
