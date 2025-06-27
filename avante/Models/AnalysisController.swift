//
//  AnalysisController.swift
//  avante
//
//  Created by Carl Osborne on 6/24/25.
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
            if activeDocument?.state.fullText != documentText {
                activeDocument?.state.fullText = documentText
                if let doc = activeDocument {
                    workspace?.markDocumentAsDirty(url: doc.url)
                }
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

    let focusEditorSubject = PassthroughSubject<Void, Never>()

    private(set) var activeDocument: AvanteDocument?
    private(set) weak var workspace: WorkspaceViewModel?

    private let jobProcessor = AnalysisJobProcessor()
    private var currentAnalysisSessionID: UUID?
    private var sessionCreationTask: Task<Void, Error>?
    private var latestGeneratedMetrics: AnalysisMetricsGroup?
    
    // ADDED: Queue and task for the re-analysis feeder
    private var reanalysisEditQueue: [Edit] = []
    private var reanalysisTotalEdits: Int = 0
    private var reanalysisTask: Task<Void, Never>?
    
    private var mouseStationaryTimer: AnyCancellable?
    private let mouseStationaryDelay = 0.8 // seconds

    // ADDED: A default completion handler to be shared by both manual and re-analysis queuing.
    // This ensures the context overflow logic is always applied.
    private lazy var defaultAnalysisCompletionHandler: @MainActor (Result<AnalysisResult, Error>, [Edit]) -> Void = { [weak self] result, processedEdits in
        guard let self = self else { return }

        switch result {
        case .success(let analysisResult):
            self.latestGeneratedMetrics = analysisResult.metrics
            self.metricsForDisplay = analysisResult.metrics
            
            // Don't overwrite re-analysis status with "Analysis complete."
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
            
            self.resolveConflictsByAdding(newEdit: newAnalyzedEdit)
    
        case .failure(let error):
            // MODIFIED: Added specific handling for the guardrail violation error.
            if self.reanalysisProgress == nil {
                 self.status = "Analysis failed."
            }

            // Check for the specific error type to provide better user feedback.
            if let generationError = error as? FoundationModels.LanguageModelSession.GenerationError,
               case .guardrailViolation = generationError {
                self.status = "Skipped sensitive content."
                // The job processor has already prevented this from being re-queued.
                // The analysis process will now continue with the next word.
            }
            else if String(describing: error).contains("Context length") {
                print("🚨 Context overflow detected! Resetting session.")
                self.resetLiveSession()
            }
        }
    }
    
    func mouseDidMove() {
        if isMouseStationary {
            isMouseStationary = false
        }
        
        mouseStationaryTimer?.cancel()
        mouseStationaryTimer = Just(())
            .delay(for: .seconds(mouseStationaryDelay), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.isMouseStationary = true
            }
    }
    
    func mouseDidExit() {
        mouseStationaryTimer?.cancel()
        if !isMouseStationary {
            isMouseStationary = true
        }
    }

    func toggleHighlight(for metric: MetricType) {
        if activeHighlight == metric {
            activeHighlight = nil
        } else {
            activeHighlight = metric
        }
    }

    func setWorkspace(_ workspace: WorkspaceViewModel) {
        self.workspace = workspace
    }

    func loadDocument(document: AvanteDocument?) {
        reanalysisTask?.cancel()
        reanalysisProgress = nil
        
        Task { await jobProcessor.clearQueue() }
        
        guard let doc = document else {
            self.activeDocument = nil
            self.documentText = ""
            self.metricsForDisplay = nil
            self.status = "Select a file to begin."
            return
        }

        if self.activeDocument?.url == doc.url { return }
        
        doc.state.analysisSessions = doc.state.analysisSessions.map { resolveConflicts(in: $0) }
        
        self.activeDocument = doc
        self.documentText = doc.state.fullText
        self.metricsForDisplay = doc.state.analysisSessions.flatMap { $0.analyzedEdits }.last?.analysisResult
        self.latestGeneratedMetrics = self.metricsForDisplay
        self.status = "Document loaded."
        
        createNewAnalysisSession()
    }

    func saveDocument() {
        guard let doc = activeDocument, let workspace = self.workspace else { return }
        
        workspace.isPerformingManualFileOperation = true
        doc.state.analysisSessions = doc.state.analysisSessions.map { resolveConflicts(in: $0) }
        doc.state.fullText = self.documentText
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
            
            if reanalysisProgress == nil {
                self.status = "Word queued..."
            }
            
            await jobProcessor.queue(edit: edit, onResult: self.defaultAnalysisCompletionHandler)
        }
    }
    
    // ADDED: Main entry point for the re-analysis feature.
    func reanalyzeActiveDocument() {
        guard let doc = activeDocument, reanalysisProgress == nil else { return }
        
        reanalysisTask?.cancel() // Cancel any previous re-analysis
        
        // 1. Clear existing analysis data
        doc.state.analysisSessions.removeAll()
        createNewAnalysisSession() // A re-analyzed doc is one big session
        self.objectWillChange.send() // Force UI to update and clear highlights
        
        // 2. Prepare a queue of edits, one for each word in the document
        let fullText = doc.state.fullText
        var edits: [Edit] = []
        
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = fullText
        
        tokenizer.enumerateTokens(in: fullText.startIndex..<fullText.endIndex) { tokenRange, _ in
            let nsRange = NSRange(tokenRange, in: fullText)
            let word = String(fullText[tokenRange])
            
            // We only want to create analysis jobs for actual words.
            if !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let edit = Edit(
                    textAdded: word,
                    range: nsRange,
                    isLinear: true,
                    fullDocumentContext: fullText
                )
                edits.append(edit)
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

        reanalysisTask = Task {
            await feedReanalysisQueue()
        }
    }
    
    // ADDED: Feeder task that queues words, waiting for the processor to be idle between each one.
    private func feedReanalysisQueue() async {
        while !reanalysisEditQueue.isEmpty {
            if Task.isCancelled {
                await MainActor.run {
                    self.reanalysisProgress = nil
                    self.status = "Re-analysis cancelled."
                }
                break
            }
            
            // This is the key: wait for the job processor to be free.
            // If it's busy (e.g., handling a context overflow reset), this will wait.
            await waitUntilJobProcessorIsIdle()
            
            guard !reanalysisEditQueue.isEmpty else { break }
            let edit = reanalysisEditQueue.removeFirst()
            
            // Update progress on the main thread
            DispatchQueue.main.async {
                let processedCount = self.reanalysisTotalEdits - self.reanalysisEditQueue.count
                let progress = Double(processedCount) / Double(self.reanalysisTotalEdits)
                self.reanalysisProgress = progress
                self.status = "Re-analyzing..."
            }
            
            // Use the standard analysis queue with the standard handler
            await jobProcessor.queue(edit: edit, onResult: self.defaultAnalysisCompletionHandler)
        }
        
        // Finished
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
    
    // ADDED: Helper to wait for the analysis processor to be idle.
    private func waitUntilJobProcessorIsIdle() async {
        while await !jobProcessor.isIdle() {
            try? await Task.sleep(nanoseconds: 10_000_000) // wait 0.1 seconds
        }
    }
    
    private func resolveConflictsByAdding(newEdit: AnalyzedEdit) {
        guard let currentID = self.currentAnalysisSessionID,
              let sessionIndex = self.activeDocument?.state.analysisSessions.firstIndex(where: { $0.id == currentID }) else { return }
        
        let newRange = NSRange(location: newEdit.range.lowerBound, length: newEdit.range.upperBound - newEdit.range.lowerBound)
        
        self.activeDocument?.state.analysisSessions[sessionIndex].analyzedEdits.removeAll { existingEdit in
            let existingRange = NSRange(location: existingEdit.range.lowerBound, length: existingEdit.range.upperBound - existingEdit.range.lowerBound)
            return NSIntersectionRange(newRange, existingRange).length > 0 || NSLocationInRange(newRange.location, existingRange)
        }
        
        self.activeDocument?.state.analysisSessions[sessionIndex].analyzedEdits.append(newEdit)
        self.activeDocument?.state.analysisSessions[sessionIndex].analyzedEdits.sort { $0.range.lowerBound < $1.range.lowerBound }
    }

    private func resolveConflicts(in session: AnalysisSession) -> AnalysisSession {
        let sortedEdits = session.analyzedEdits.sorted { $0.timestamp > $1.timestamp }
        var cleanedEdits: [AnalyzedEdit] = []
        
        for editToAdd in sortedEdits {
            let nsRangeToAdd = NSRange(location: editToAdd.range.lowerBound, length: editToAdd.range.upperBound - editToAdd.range.lowerBound)
            
            let hasConflict = cleanedEdits.contains { existingEdit in
                let existingNSRange = NSRange(location: existingEdit.range.lowerBound, length: existingEdit.range.upperBound - existingEdit.range.lowerBound)
                return NSIntersectionRange(nsRangeToAdd, existingNSRange).length > 0
            }
            
            if !hasConflict {
                cleanedEdits.append(editToAdd)
            }
        }
        
        var cleanedSession = session
        cleanedSession.analyzedEdits = cleanedEdits.sorted { $0.range.lowerBound < $1.range.lowerBound }
        return cleanedSession
    }
    
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
    
    func handleDeletion(at location: Int) {
        guard activeDocument != nil else { return }
        
        var hasInvalidatedData = false
        
        // Iterate through all analysis sessions and remove any analyzed edits
        // that are now invalid because they came at or after the deletion point.
        for i in 0..<(activeDocument?.state.analysisSessions.count ?? 0) {
            let originalCount = activeDocument!.state.analysisSessions[i].analyzedEdits.count
            activeDocument?.state.analysisSessions[i].analyzedEdits.removeAll { edit in
                // If an edit starts at or after the deletion location, its range is now wrong.
                return edit.range.lowerBound >= location
            }
            if activeDocument!.state.analysisSessions[i].analyzedEdits.count != originalCount {
                hasInvalidatedData = true
            }
        }
        
        // If we removed any data, the UI needs to be redrawn to remove highlights.
        if hasInvalidatedData {
            objectWillChange.send()
        }

        // A deletion is a non-linear edit. We must create a new analysis
        // session to ensure correct context for any new text that is typed.
        createNewAnalysisSession(at: location)
    }

    private func createNewAnalysisSession(at location: Int? = nil) {
        print("SESSION BREAK: Creating new analysis session in data model.")
        
        let newSession = AnalysisSession(startLocation: location ?? 0, contextSummary: "", analyzedEdits: [])
        self.activeDocument?.state.analysisSessions.append(newSession)
        self.currentAnalysisSessionID = newSession.id
        
        resetLiveSession()
    }
    
    private func resetLiveSession() {
        sessionCreationTask = Task {
            // During re-analysis, the status is controlled by the feeder, so don't show "Priming..."
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
