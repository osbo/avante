//
//  AnalysisController.swift
//  avante
//
//  Created by Carl Osborne on 6/25/25.
//

import Foundation
import SwiftUI
import FoundationModels
import Combine
import NaturalLanguage

struct Edit {
    let textAdded: String
    let range: NSRange
    let isLinear: Bool
    let fullDocumentContext: String
}

@MainActor
class AnalysisController: ObservableObject {
    @Published var documentText: String = "" {
        didSet {
            if let doc = activeDocument, doc.state.fullText != documentText {
                doc.updateFullText(to: documentText)
                workspace?.markDocumentAsDirty(url: doc.url)
            }
        }
    }
    
    @AppStorage("activeHighlight") private var activeHighlightRaw: String = ""
    var activeHighlight: MetricType? {
        get { MetricType(rawValue: activeHighlightRaw) }
        set { activeHighlightRaw = newValue?.rawValue ?? "" }
    }
    @Published private(set) var metricsForDisplay: AnalysisMetricsGroup?
    @Published private(set) var status: String = "Select a file to begin."
    @Published private(set) var reanalysisProgress: Double? = nil
    @Published var isFocusModeEnabled: Bool = false
    @Published var isMouseStationary = true
    @Published var textViewSelectionRange = NSRange(location: 0, length: 0)
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false

    let focusEditorSubject = PassthroughSubject<Void, Never>()
    let forceSetSelectionSubject = PassthroughSubject<NSRange, Never>()

    private(set) var activeDocument: AvanteDocument?
    private(set) weak var workspace: WorkspaceViewModel?

    private let jobProcessor = AnalysisJobProcessor()
    private var sessionCreationTask: Task<Void, Error>?
    private var latestGeneratedMetrics: AnalysisMetricsGroup?
    
    private var reanalysisEditQueue: [Edit] = []
    private var reanalysisTotalEdits: Int = 0
    private var reanalysisTask: Task<Void, Never>?
    
    private var mouseStationaryTimer: AnyCancellable?
    private let mouseStationaryDelay = 0.8 // seconds
    private var undoRedoStateCancellable: AnyCancellable?

    private lazy var defaultAnalysisCompletionHandler: @MainActor (Result<AnalysisResult, Error>, [Edit]) -> Void = { [weak self] result, processedEdits in
        guard let self = self else { return }

        switch result {
        case .success(let analysisResult):
            self.latestGeneratedMetrics = analysisResult.metrics
            self.metricsForDisplay = analysisResult.metrics
            
            if self.reanalysisProgress == nil {
                self.status = "Analysis complete."
            }

            guard let firstEdit = processedEdits.first, let lastEdit = processedEdits.last else { return }
            
            let newAnalysis = Analysis(
                range: CodableRange(from: NSRange(location: firstEdit.range.location, length: NSMaxRange(lastEdit.range) - firstEdit.range.location)),
                metrics: analysisResult.metrics
            )
            
            self.activeDocument?.addAnalysis(newAnalysis)
    
        case .failure(let error):
            if self.reanalysisProgress == nil {
                 self.status = "Analysis failed."
            }

            if let generationError = error as? FoundationModels.LanguageModelSession.GenerationError,
               case .guardrailViolation = generationError {
                self.status = "Skipped sensitive content."
            }
            else if String(describing: error).contains("Context length") {
                print("🚨 Context overflow detected! Resetting session.")
                self.resetLiveSession()
            }
        }
    }
    
    func mouseDidMove() {
        if isMouseStationary { isMouseStationary = false }
        mouseStationaryTimer?.cancel()
        mouseStationaryTimer = Just(())
            .delay(for: .seconds(mouseStationaryDelay), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.isMouseStationary = true }
    }
    
    func mouseDidExit() {
        mouseStationaryTimer?.cancel()
        if !isMouseStationary { isMouseStationary = true }
    }

    func toggleHighlight(for metric: MetricType) {
        activeHighlight = (activeHighlight == metric) ? nil : metric
    }

    func setWorkspace(_ workspace: WorkspaceViewModel) {
        self.workspace = workspace
    }
    
    func loadDocument(document: AvanteDocument?) {
        reanalysisTask?.cancel()
        reanalysisProgress = nil
        Task { await jobProcessor.clearQueue() }
        undoRedoStateCancellable?.cancel()
        
        guard let doc = document else {
            self.activeDocument = nil
            self.documentText = ""
            self.metricsForDisplay = nil
            self.status = "Select a file to begin."
            self.canUndo = false
            self.canRedo = false
            return
        }
        
        // REMOVED: This method no longer exists on AvanteDocument
        // doc.performInitialConflictResolution()
        
        self.activeDocument = doc

        self.undoRedoStateCancellable = doc.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self = self, let doc = self.activeDocument else { return }
                
                self.documentText = newState.fullText
                // MODIFIED: Use the new 'analyses' array and its 'metrics' property
                self.metricsForDisplay = newState.analyses.last?.metrics
                self.latestGeneratedMetrics = self.metricsForDisplay
                
                if let selection = newState.selectionRange {
                    self.textViewSelectionRange = NSRange(location: selection.lowerBound, length: selection.upperBound - selection.lowerBound)
                }

                if self.canUndo != doc.canUndo { self.canUndo = doc.canUndo }
                if self.canRedo != doc.canRedo { self.canRedo = doc.canRedo }
            }
        
        doc.objectWillChange.send()
        
        // MODIFIED: We no longer have a concept of a session at the document level
        resetLiveSession()
    }

    func saveDocument() {
        guard let doc = activeDocument, let workspace = self.workspace else { return }
        
        workspace.isPerformingManualFileOperation = true
        // REMOVED: This method no longer exists on AvanteDocument
        // doc.performInitialConflictResolution()
        doc.updateFullText(to: self.documentText)
        doc.save()
        workspace.markDocumentAsClean(url: doc.url)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            workspace.isPerformingManualFileOperation = false
        }
    }
    
    // MODIFIED: Simplified queueing logic
    func queueForAnalysis(edit: Edit) {
        if !edit.isLinear {
            // A non-linear edit (e.g., pasting text) now just resets the live AI session
            // to ensure it has the latest full context.
            resetLiveSession()
        }
        
        Task {
            _ = await sessionCreationTask?.result
            if reanalysisProgress == nil { self.status = "Word queued..." }
            await jobProcessor.queue(edit: edit, onResult: self.defaultAnalysisCompletionHandler)
        }
    }
    
    func reanalyzeActiveDocument() {
        guard let doc = activeDocument, reanalysisProgress == nil else { return }
        
        reanalysisTask?.cancel()
        
        doc.clearAnalyses()
        self.objectWillChange.send()
        
        let fullText = doc.state.fullText
        var edits: [Edit] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = fullText
        
        tokenizer.enumerateTokens(in: fullText.startIndex..<fullText.endIndex) { tokenRange, _ in
            let nsRange = NSRange(tokenRange, in: fullText)
            let word = String(fullText[tokenRange])
            
            if !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                edits.append(Edit(textAdded: word, range: nsRange, isLinear: true, fullDocumentContext: fullText))
            }
            return true
        }
        
        guard !edits.isEmpty else {
            status = "Document is empty."
            return
        }

        self.reanalysisEditQueue = edits
        self.reanalysisTotalEdits = edits.count
        self.reanalysisProgress = 0.0
        self.status = "Re-analyzing..."

        reanalysisTask = Task { await feedReanalysisQueue() }
    }
    
    private func feedReanalysisQueue() async {
        // ... (this method remains the same)
        while !reanalysisEditQueue.isEmpty {
            if Task.isCancelled {
                await MainActor.run {
                    self.reanalysisProgress = nil
                    self.status = "Re-analysis cancelled."
                }
                break
            }
            
            while await !jobProcessor.isIdle() {
                try? await Task.sleep(nanoseconds: 10_000_000) // 0.1 seconds
            }
            
            guard !reanalysisEditQueue.isEmpty else { break }
            let edit = reanalysisEditQueue.removeFirst()
            
            await jobProcessor.queue(edit: edit, onResult: self.defaultAnalysisCompletionHandler)
            
            DispatchQueue.main.async {
                let processedCount = self.reanalysisTotalEdits - self.reanalysisEditQueue.count
                self.reanalysisProgress = Double(processedCount) / Double(self.reanalysisTotalEdits)
                self.status = "Re-analyzing..."
            }
        }
        
        if !Task.isCancelled {
            await MainActor.run {
                self.reanalysisProgress = nil
                self.status = "Re-analysis complete."
                if let doc = activeDocument {
                    workspace?.markDocumentAsDirty(url: doc.url)
                }
            }
        }
    }
    
    func recordUndoState() {
        activeDocument?.updateSelectionState(to: self.textViewSelectionRange)
        activeDocument?.recordNewState()
    }
    
    private func syncState(from documentState: DocumentState?) {
        guard let state = documentState else { return }

        self.documentText = state.fullText
        // MODIFIED: Use the new 'analyses' array
        self.metricsForDisplay = state.analyses.last?.metrics
        self.latestGeneratedMetrics = self.metricsForDisplay
        
        if let selection = state.selectionRange {
            self.textViewSelectionRange = NSRange(location: selection.lowerBound, length: selection.upperBound - selection.lowerBound)
        }
    }
    
    func undo() {
        guard let doc = activeDocument, doc.canUndo else { return }
        if let newState = doc.undo() {
            syncState(from: newState)
            if let selection = newState.selectionRange {
                let range = NSRange(location: selection.lowerBound, length: selection.upperBound - selection.lowerBound)
                forceSetSelectionSubject.send(range)
            }
        }
    }

    func redo() {
        guard let doc = activeDocument, doc.canRedo else { return }
        if let newState = doc.redo() {
            syncState(from: newState)
            if let selection = newState.selectionRange {
                let range = NSRange(location: selection.lowerBound, length: selection.upperBound - selection.lowerBound)
                forceSetSelectionSubject.send(range)
            }
        }
    }
    
    func updateMetricsForCursor(at position: Int) {
        // 1. Get the new 'analyses' array from the active document's state.
        guard let allAnalyses = activeDocument?.state.analyses, !allAnalyses.isEmpty else {
            metricsForDisplay = nil
            return
        }

        // 2. Check if the cursor is currently inside the range of a specific analysis.
        if let currentAnalysis = allAnalyses.first(where: { NSLocationInRange(position, NSRange(location: $0.range.lowerBound, length: $0.range.upperBound - $0.range.lowerBound)) }) {
            metricsForDisplay = currentAnalysis.metrics
        
        // 3. REIMPLEMENTED: If not, find the last analysis that the cursor is positioned after.
        // This is the logic that restores your desired feature.
        } else if let precedingAnalysis = allAnalyses.filter({ $0.range.upperBound <= position }).last {
            metricsForDisplay = precedingAnalysis.metrics
            
        // 4. As a fallback (e.g., cursor at the start of the doc), clear the metrics.
        } else {
            metricsForDisplay = nil
        }
    }
    
    func adjustAnalysisRanges(for changeInLength: Int, at location: Int) {
        guard let doc = activeDocument, changeInLength != 0 else { return }
        doc.adjustAnalysisRanges(for: changeInLength, at: location)
        workspace?.markDocumentAsDirty(url: doc.url)
        objectWillChange.send()
    }

    // DELETED: The createNewAnalysisSession method is no longer needed.
    
    private func resetLiveSession() {
        sessionCreationTask = Task {
            if reanalysisProgress == nil {
                self.status = "Priming session..."
            }
            
            await jobProcessor.resetSessionState()
            
            let context = self.documentText
            let instructions = Instructions(Prompting.analysisInstructions)
            let session = LanguageModelSession(instructions: instructions)
            
            if !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let primingPrompt = Prompt("Here is the document's full context. Process it and prepare for incremental analysis prompts: \n---\n\(context)\n---")
                _ = try await session.respond(to: primingPrompt)
            }
            
            // REMOVED: No more session ID logic
            
            await jobProcessor.set(session: session)
            
            if reanalysisProgress == nil {
                self.status = "Ready."
            }
            print("✅ Live session primed and set successfully.")
        }
    }
}

private enum Prompting {
    static let analysisInstructions = """
    You are a writing analyst. For each text chunk, provide scores for Novelty, Clarity, and Flow. Respond ONLY with the generable JSON for AnalysisMetricsResponse. Use a a scale where 0.00 is the lowest/worst score and 1.00 is the highest/best.
    """
}

extension CodableRange {
    init(from nsRange: NSRange) {
        self.lowerBound = nsRange.location
        self.upperBound = NSMaxRange(nsRange)
    }
}
