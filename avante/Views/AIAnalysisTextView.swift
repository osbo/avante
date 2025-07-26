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
    weak var coordinator: AIAnalysisTextView.Coordinator?

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
    
    override func keyDown(with event: NSEvent) {
        // Handle Tab key or Right Arrow key to accept autocomplete suggestion
        if coordinator?.currentSuggestionRange != nil && (event.keyCode == 48 || event.keyCode == 124) { // Tab key or Right Arrow
            coordinator?.acceptAutocompleteSuggestion()
            return
        }
        
        // For any other key, clear the suggestion first
        if coordinator?.currentSuggestionRange != nil {
            coordinator?.clearAutocompleteSuggestion()
            // Give the text storage a moment to update before processing the key
            DispatchQueue.main.async {
                super.keyDown(with: event)
            }
            return
        }
        
        super.keyDown(with: event)
    }
}


struct AIAnalysisTextView: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var analysisController: AnalysisController

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = FocusAwareTextView()
        
        textView.analysisController = context.coordinator.controller
        textView.coordinator = context.coordinator
        
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
        textView.allowsUndo = false

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
            textView.string = self.text
            
            // REMOVED: All selection logic is gone from here. It is now
            // handled by the explicit command pipeline.
            
            DispatchQueue.main.async {
                context.coordinator.isUpdatingFromModel = false
            }
        }
        
        // Initialize sentence ranges for autocomplete if not already done
        if context.coordinator.sentenceRanges.isEmpty {
            context.coordinator.updateSentenceRanges(for: textView.string)
        }
        
        // Update analysis and highlight data
        let allAnalyses = analysisController.activeDocument?.state.analyses ?? []
        layoutManager.analysisData = allAnalyses
        layoutManager.activeHighlight = analysisController.activeHighlight
        
        // Invalidate display to force a redraw of highlights
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
        
        // Autocomplete debouncing
        private var editingDebounceSubject = PassthroughSubject<Void, Never>()
        private var editingDebounceTimer: Timer?
        
        // Sentence tracking for autocomplete
        var sentenceRanges: [NSRange] = []
        
         // Autocomplete suggestion tracking
        var currentSuggestionRange: NSRange?
        var currentSuggestionText: String = ""
        var autocompleteRequestId: UUID = UUID() // Track autocomplete requests
        
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
            controller.forceSetSelectionSubject
                .receive(on: DispatchQueue.main)
                .sink { [weak self] rangeToSet in
                    // Directly set the text view's selection when the command is received.
                    self?.textView?.selectedRange = rangeToSet
                }
                .store(in: &cancellables)
            
            // Set up autocomplete debouncing
            editingDebounceSubject
                .debounce(for: .milliseconds(1000), scheduler: RunLoop.main)
                .sink { [weak self] in
                    guard let self = self,
                          let textView = self.textView else { return }
                    
                    // Flush any remaining word buffer before autocomplete
                    if !self.wordBuffer.isEmpty {
                        let cursorPosition = textView.selectedRange().location
                        self.flushWordBuffer(at: cursorPosition)
                    }
                    
                    let fullText = self.parent.text
                    let cursorPosition = textView.selectedRange().location
                    
                    // Generate a new request ID for this autocomplete request
                    let requestId = UUID()
                    self.autocompleteRequestId = requestId
                    
                    Autocomplete.autocomplete(fullText: fullText, cursorPosition: cursorPosition, sentenceRanges: self.sentenceRanges, coordinator: self, requestId: requestId)
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
            
            // Restore autocomplete suggestion color if there is one
            if let suggestionRange = currentSuggestionRange,
               suggestionRange.location >= 0,
               NSMaxRange(suggestionRange) <= textStorage.length {
                textStorage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: suggestionRange)
            }
            
            textStorage.endEditing()
        }

        // MARK: - Delegate Methods
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let selectionRange = textView.selectedRange()

            // This is the correct pattern to fix the warning. We defer the state
            // update to the next run loop cycle. Because the rest of our logic
            // is now correct, this will no longer cause cursor placement bugs.
            DispatchQueue.main.async {
                // 1. Update the controller's state from the view.
                self.controller.textViewSelectionRange = selectionRange
                self.controller.updateMetricsForCursor(at: selectionRange.location)
                
                // 2. Now that the controller's state is fresh, update the focus effect.
                self.updateFocus(on: textView)
            }
        }
        
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            
            // This guard correctly prevents this logic from running when the text is
            // being updated programmatically (e.g., during an undo operation).
            guard !isUpdatingFromModel else { return }
            guard editedMask.contains(.editedCharacters) else { return }
            
            // The operations below are now synchronous, eliminating the race condition.
            
            let newText = textStorage.string
            self.parent.text = newText // Update the SwiftUI-managed state.
            
            // Adjust existing analysis data to account for the text change.
            if delta != 0 {
                self.controller.adjustAnalysisRanges(for: delta, at: editedRange.location)
            }

            // If text was added (not just deleted), process it for new analysis.
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
            
            // Update sentence ranges for autocomplete
            updateSentenceRanges(for: newText)
            
            // Trigger autocomplete debouncing
            editingDebounceSubject.send()
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
            
            self.controller.recordUndoState()

            let edit = Edit(
                textAdded: word,
                range: wordRange,
                isLinear: true,
                fullDocumentContext: fullText
            )
            
            controller.queueForAnalysis(edit: edit)
        }
        
        // MARK: - Sentence Tracking
        
        func updateSentenceRanges(for text: String) {
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = text
            
            sentenceRanges.removeAll()
            
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
                let nsRange = NSRange(tokenRange, in: text)
                sentenceRanges.append(nsRange)
                return true
            }
        }
        
        // MARK: - Autocomplete Display
        
        func displayAutocompleteSuggestion(_ suggestion: String, at cursorPosition: Int, requestId: UUID) {
            guard let textView = textView,
                  let textStorage = textView.textStorage,
                  !suggestion.isEmpty else { return }
            
            // Check if this request is still valid (user hasn't started typing again)
            guard requestId == autocompleteRequestId else {
                print("Autocomplete request \(requestId) is stale, ignoring suggestion")
                return
            }
            
            // Get the current cursor position from the text view
            let currentCursorPosition = textView.selectedRange().location
            
            // Validate cursor position
            guard currentCursorPosition >= 0,
                  currentCursorPosition <= textStorage.length else {
                print("Warning: Invalid cursor position \(currentCursorPosition) for text length \(textStorage.length)")
                return
            }
            
            print("Displaying suggestion '\(suggestion)' at cursor position \(currentCursorPosition), text length: \(textStorage.length)")
            
            // Clear any existing suggestion first
            clearAutocompleteSuggestion()
            
            // Set flag to prevent processing this change as user input
            isUpdatingFromModel = true
            
            // Begin editing to make this atomic
            textStorage.beginEditing()
            
            // Check if we need to add a space before the suggestion
            let needsSpace = currentCursorPosition > 0 && 
                           !textStorage.string[textStorage.string.index(textStorage.string.startIndex, offsetBy: currentCursorPosition - 1)].isWhitespace
            
            // Prepare the text to insert (add space if needed)
            let textToInsert = needsSpace ? " \(suggestion)" : suggestion
            
            // Insert the suggestion text AFTER the cursor position
            let suggestionRange = NSRange(location: currentCursorPosition, length: 0)
            textStorage.replaceCharacters(in: suggestionRange, with: textToInsert)
            
            // Apply accent color to make it appear as a suggestion
            let suggestionColor = NSColor.controlAccentColor
            let newSuggestionRange = NSRange(location: currentCursorPosition, length: textToInsert.count)
            textStorage.addAttribute(.foregroundColor, value: suggestionColor, range: newSuggestionRange)
            
            // End editing to commit all changes atomically
            textStorage.endEditing()
            
            // Track the suggestion
            currentSuggestionRange = newSuggestionRange
            currentSuggestionText = suggestion
            
            // Update the parent text binding
            parent.text = textStorage.string
            
            // Keep cursor at original position (don't move it to the end)
            textView.setSelectedRange(NSRange(location: currentCursorPosition, length: 0))
            
            // Reset the flag
            DispatchQueue.main.async {
                self.isUpdatingFromModel = false
            }
        }
        
        func clearAutocompleteSuggestion() {
            guard let textView = textView,
                  let textStorage = textView.textStorage,
                  let suggestionRange = currentSuggestionRange else { return }
            
            // Validate the range is still valid
            guard suggestionRange.location >= 0,
                  NSMaxRange(suggestionRange) <= textStorage.length else {
                print("Warning: Invalid suggestion range \(suggestionRange) for text length \(textStorage.length)")
                // Clear tracking even if range is invalid
                currentSuggestionRange = nil
                currentSuggestionText = ""
                return
            }
            
            // Set flag to prevent processing this change as user input
            isUpdatingFromModel = true
            
            // Begin editing to make this atomic
            textStorage.beginEditing()
            
            // Remove the suggestion text
            textStorage.replaceCharacters(in: suggestionRange, with: "")
            
            // End editing to commit all changes atomically
            textStorage.endEditing()
            
            // Clear tracking
            currentSuggestionRange = nil
            currentSuggestionText = ""
            
            // Update the parent text binding
            parent.text = textStorage.string
            
            // Reset the flag
            DispatchQueue.main.async {
                self.isUpdatingFromModel = false
            }
        }
        
        func acceptAutocompleteSuggestion() {
            guard let textView = textView,
                  let textStorage = textView.textStorage,
                  let suggestionRange = currentSuggestionRange else { return }
            
            // Validate the range is still valid
            guard suggestionRange.location >= 0,
                  NSMaxRange(suggestionRange) <= textStorage.length else {
                print("Warning: Invalid suggestion range \(suggestionRange) for text length \(textStorage.length)")
                // Clear tracking even if range is invalid
                currentSuggestionRange = nil
                currentSuggestionText = ""
                return
            }
            
            // Set flag to prevent processing this change as user input
            isUpdatingFromModel = true
            
            // Begin editing to make this atomic
            textStorage.beginEditing()
            
            // Remove the secondary label color and set it to normal text color
            textStorage.removeAttribute(.foregroundColor, range: suggestionRange)
            textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: suggestionRange)
            
            // End editing to commit all changes atomically
            textStorage.endEditing()
            
            // Move cursor to the end of the accepted text
            let newCursorPosition = NSMaxRange(suggestionRange)
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
            
            // Clear tracking
            currentSuggestionRange = nil
            currentSuggestionText = ""
            
            // Reset the flag
            DispatchQueue.main.async {
                self.isUpdatingFromModel = false
            }
        }
        

    }
}
