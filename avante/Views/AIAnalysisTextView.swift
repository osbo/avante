

import SwiftUI
import AppKit
import Combine

struct AIAnalysisTextView: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var analysisController: AnalysisController

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        
        textView.drawsBackground = false
        
        textView.autoresizingMask = [.width, .height]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.font = .systemFont(ofSize: 16, weight: .regular)
        textView.textColor = .textColor
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
        
        // The coordinator needs to be the delegate for both text changes and selection changes.
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
        
        if let textContainer = textView.textContainer {
            let visibleRect = nsView.documentVisibleRect
            let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            layoutManager.invalidateDisplay(forGlyphRange: visibleGlyphRange)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, controller: analysisController)
    }

    // FIX: Coordinator now also conforms to NSTextViewDelegate to hear about selection changes.
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
        
        // FIX: This delegate method is called whenever the cursor moves.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let cursorPosition = textView.selectedRange().location
            // Report the new position to the controller so it can update the dials.
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
