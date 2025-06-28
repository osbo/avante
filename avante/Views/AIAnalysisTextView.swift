//
//  AIAnalysisTextView.swift
//  avante
//
//  Created by Carl Osborne on 6/24/25.
//

import SwiftUI
import AppKit
import Combine
import NaturalLanguage

fileprivate extension String {
    func sentenceRange(for location: Int) -> NSRange {
        guard let targetIndex = Range(NSRange(location: location, length: 0), in: self)?.lowerBound else {
            return NSRange(location: location, length: 0)
        }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = self
        var resultingRange = NSRange(location: location, length: 0)

        tokenizer.enumerateTokens(in: self.startIndex..<self.endIndex) { tokenRange, _ in
            if tokenRange.contains(targetIndex) || (targetIndex == tokenRange.upperBound && !tokenRange.isEmpty) {
                resultingRange = NSRange(tokenRange, in: self)
                return false
            }
            return true
        }
        
        return resultingRange
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
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8
        textView.defaultParagraphStyle = paragraphStyle
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
        
        private let wordSeparators: CharacterSet = {
            var separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
            // Exclude characters that are often part of a word.
            separators.remove(charactersIn: "'’") // Apostrophes
            separators.remove(charactersIn: "-")   // Hyphen
            return separators
        }()
        
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
            
            let isEditorFocused = (textView.window?.firstResponder == textView)

            let shouldDim = controller.isFocusModeEnabled &&
                            controller.isMouseStationary &&
                            controller.textViewSelectionRange.length == 0 &&
                            controller.activeHighlight == nil &&
                            isEditorFocused

            let fullRange = NSRange(location: 0, length: textStorage.length)
            
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
            
            let selectionRange = textView.selectedRange()
            
            DispatchQueue.main.async {
                self.controller.textViewSelectionRange = selectionRange
                self.controller.updateMetricsForCursor(at: selectionRange.location)
            }
        }
        
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            
            guard !isUpdatingFromModel else { return }
            guard editedMask.contains(.editedCharacters) else { return }
            
            let newText = textStorage.string
            
            DispatchQueue.main.async {
                self.parent.text = newText
                
                // If the length of the text changed (an insertion or deletion occurred)...
                if delta != 0 {
                    // Call the new, unified function to adjust all stored analysis ranges.
                    self.controller.adjustAnalysisRanges(for: delta, at: editedRange.location)
                }

                // If text was added, we still process the new characters for live analysis.
                if delta > 0 {
                    let addedText = (newText as NSString).substring(with: editedRange)
                    for (offset, character) in addedText.enumerated() {
                        let characterLocation = editedRange.location + offset
                        
                        if character.unicodeScalars.allSatisfy(self.wordSeparators.contains) {
                            self.flushWordBuffer(at: characterLocation)
                        } else {
                            self.wordBuffer.append(character)
                        }
                    }
                }
            }
        }
        
        private func flushWordBuffer(at separatorLocation: Int) {
            guard !wordBuffer.isEmpty else { return }
            
            let word = wordBuffer
            self.wordBuffer = ""

            let wordLocation = separatorLocation - word.count
            let wordRange = NSRange(location: wordLocation, length: word.count)
            
            // MODIFIED: Use the synchronized parent binding as the source of truth for the full text.
            let fullText = self.parent.text
            
            // Safety check against the now-guaranteed-to-be-current text model.
            guard wordLocation >= 0, NSMaxRange(wordRange) <= (fullText as NSString).length else { return }

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
