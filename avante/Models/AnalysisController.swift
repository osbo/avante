// AnalysisController.swift

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
            // MODIFIED: Call the new method on the document model.
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

    private(set) var activeDocument: AvanteDocument?
    private(set) weak var workspace: WorkspaceViewModel?

    private let jobProcessor = AnalysisJobProcessor()
    private var currentAnalysisSessionID: UUID?
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
            let combinedRange = NSRange(location: firstEdit.range.location, length: NSMaxRange(lastEdit.range) - firstEdit.range.location)
            let combinedText = processedEdits.map(\.textAdded).joined(separator: " ")

            let newAnalyzedEdit = AnalyzedEdit(
                range: CodableRange(from: combinedRange),
                text: combinedText,
                analysisResult: analysisResult.metrics
            )
            
            // MODIFIED: Use the new document method to add the edit.
            if let sessionID = self.currentAnalysisSessionID {
                self.activeDocument?.addAnalyzedEdit(newAnalyzedEdit, toSessionWithID: sessionID)
            }
    
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
        
        doc.performInitialConflictResolution()
        self.activeDocument = doc

        self.undoRedoStateCancellable = doc.$state
            .receive(on: DispatchQueue.main) // Ensure the sink block runs on the main thread.
            .sink { [weak self] newState in
                // The DispatchQueue.main.async wrapper is no longer needed here.
                guard let self = self, let doc = self.activeDocument else { return }
                
                self.documentText = newState.fullText
                self.metricsForDisplay = newState.analysisSessions.flatMap { $0.analyzedEdits }.last?.analysisResult
                self.latestGeneratedMetrics = self.metricsForDisplay
                
                if let selection = newState.selectionRange {
                    self.textViewSelectionRange = NSRange(location: selection.lowerBound, length: selection.upperBound - selection.lowerBound)
                }

                if self.canUndo != doc.canUndo { self.canUndo = doc.canUndo }
                if self.canRedo != doc.canRedo { self.canRedo = doc.canRedo }
            }
        
        doc.objectWillChange.send()
        
        createNewAnalysisSession()
    }

    func saveDocument() {
        guard let doc = activeDocument, let workspace = self.workspace else { return }
        
        workspace.isPerformingManualFileOperation = true
        // MODIFIED: Call the new methods on the document model.
        doc.performInitialConflictResolution()
        doc.updateFullText(to: self.documentText)
        doc.save()
        workspace.markDocumentAsClean(url: doc.url)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            workspace.isPerformingManualFileOperation = false
        }
    }
    
    func queueForAnalysis(edit: Edit) {
        if !edit.isLinear {
            createNewAnalysisSession(at: edit.range.location)
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
        
        // MODIFIED: Call the new method on the document model.
        doc.clearAnalysisSessions()
        createNewAnalysisSession()
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
        while !reanalysisEditQueue.isEmpty {
            if Task.isCancelled {
                await MainActor.run {
                    self.reanalysisProgress = nil
                    self.status = "Re-analysis cancelled."
                }
                break
            }
            
            _ = await jobProcessor.isIdle()
            
            guard !reanalysisEditQueue.isEmpty else { break }
            let edit = reanalysisEditQueue.removeFirst()
            
            DispatchQueue.main.async {
                let processedCount = self.reanalysisTotalEdits - self.reanalysisEditQueue.count
                self.reanalysisProgress = Double(processedCount) / Double(self.reanalysisTotalEdits)
                self.status = "Re-analyzing..."
            }
            
            await jobProcessor.queue(edit: edit, onResult: self.defaultAnalysisCompletionHandler)
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
        self.activeDocument?.recordNewState()
    }
    
    private func syncState(from documentState: DocumentState?) {
        guard let state = documentState else { return }

        self.documentText = state.fullText
        self.metricsForDisplay = state.analysisSessions.flatMap { $0.analyzedEdits }.last?.analysisResult
        self.latestGeneratedMetrics = self.metricsForDisplay
        
        if let selection = state.selectionRange {
            self.textViewSelectionRange = NSRange(location: selection.lowerBound, length: selection.upperBound - selection.lowerBound)
        }
    }

    // REPLACE your existing undo() method with this.
    func undo() {
        guard let doc = activeDocument, doc.canUndo else { return }
        // The document now returns the new state directly.
        let newState = doc.undo()
        // Immediately sync the controller with this definitive new state.
        syncState(from: newState)
    }

    // REPLACE your existing redo() method with this.
    func redo() {
        guard let doc = activeDocument, doc.canRedo else { return }
        // The document now returns the new state directly.
        let newState = doc.redo()
        // Immediately sync the controller with this definitive new state.
        syncState(from: newState)
    }
    
    // REMOVED: This logic now lives in AvanteDocument.swift
    // private func resolveConflictsByAdding(...) { ... }
    
    // REMOVED: This logic now lives in AvanteDocument.swift
    // private func resolveConflicts(in session: AnalysisSession) -> AnalysisSession { ... }
    
    func updateMetricsForCursor(at position: Int) {
        guard let allEdits = activeDocument?.state.analysisSessions.flatMap({ $0.analyzedEdits }), !allEdits.isEmpty else {
            metricsForDisplay = nil
            return
        }

        if let currentEdit = allEdits.first(where: { NSLocationInRange(position, NSRange(location: $0.range.lowerBound, length: $0.range.upperBound - $0.range.lowerBound)) }) {
            metricsForDisplay = currentEdit.analysisResult
        } else if let precedingEdit = allEdits.filter({ $0.range.upperBound <= position }).last {
            metricsForDisplay = precedingEdit.analysisResult
        } else {
            metricsForDisplay = latestGeneratedMetrics
        }
    }
    
    func adjustAnalysisRanges(for changeInLength: Int, at location: Int) {
        // MODIFIED: Delegate this call to the document model.
        guard let doc = activeDocument, changeInLength != 0 else { return }
        doc.adjustAnalysisRanges(for: changeInLength, at: location)
        workspace?.markDocumentAsDirty(url: doc.url)
        objectWillChange.send()
    }

    private func createNewAnalysisSession(at location: Int? = nil) {
        print("SESSION BREAK: Creating new analysis session in data model.")
        
        let newSession = AnalysisSession(startLocation: location ?? 0, contextSummary: "", analyzedEdits: [])
        // MODIFIED: Call the new method on the document model.
        self.activeDocument?.addNewAnalysisSession(newSession)
        self.currentAnalysisSessionID = newSession.id
        
        resetLiveSession()
    }
    
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
            
            if self.currentAnalysisSessionID == nil {
                self.currentAnalysisSessionID = self.activeDocument?.state.analysisSessions.last?.id
            }
            
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
