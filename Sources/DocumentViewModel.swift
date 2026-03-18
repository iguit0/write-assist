// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

@preconcurrency import AppKit
import os

private let logger = Logger(subsystem: "com.writeassist", category: "DocumentViewModel")

@MainActor
@Observable
public final class DocumentViewModel: @unchecked Sendable {
    public var text: String = ""
    var issues: [WritingIssue] = []

    /// IDs of issues that arrived since the popover was last opened.
    var unseenIssueIDs: Set<String> = []

    var onNewIssuesReadyForHUD: (([WritingIssue]) -> Void)?
    var onCorrectionApplied: ((WritingIssue, String) -> Void)?

    public weak var inputMonitor: GlobalInputMonitor? {
        didSet { correctionApplicator.markInputMonitor(inputMonitor) }
    }

    private(set) var cachedAnalysis: NLAnalysis?
    private(set) var metrics: DocumentMetrics

    private let issueGatekeeper: IssueGatekeeper
    private let correctionApplicator: CorrectionApplicator
    private let writingStatsStore: WritingStatsStore
    private let ignoreRulesStore: IgnoreRulesStore
    private let preferencesManager: PreferencesManager

    private var checkTask: Task<Void, Never>?
    private var checkGeneration = 0

    public init() {
        let writingStatsStore = WritingStatsStore.shared
        self.issueGatekeeper = IssueGatekeeper()
        self.writingStatsStore = writingStatsStore
        self.correctionApplicator = CorrectionApplicator(writingStatsStore: writingStatsStore)
        self.ignoreRulesStore = .shared
        self.preferencesManager = .shared
        self.metrics = .build(text: "", analysis: nil, issues: [])
        wireCallbacks()
    }

    init(
        issueGatekeeper: IssueGatekeeper,
        writingStatsStore: WritingStatsStore = .shared,
        ignoreRulesStore: IgnoreRulesStore = .shared,
        preferencesManager: PreferencesManager = .shared
    ) {
        self.issueGatekeeper = issueGatekeeper
        self.writingStatsStore = writingStatsStore
        self.correctionApplicator = CorrectionApplicator(writingStatsStore: writingStatsStore)
        self.ignoreRulesStore = ignoreRulesStore
        self.preferencesManager = preferencesManager
        self.metrics = .build(text: "", analysis: nil, issues: [])
        wireCallbacks()
    }

    private func wireCallbacks() {
        correctionApplicator.onCorrectionApplied = { [weak self] issue, correction in
            self?.onCorrectionApplied?(issue, correction)
        }
    }

    var isCorrectionInFlight: Bool { correctionApplicator.isCorrectionInFlight }
    var detectedTone: DetectedTone { metrics.detectedTone }

    func markAllSeen() {
        unseenIssueIDs = issueGatekeeper.markAllSeen()
    }

    // MARK: - Forwarded metrics

    var wordCount: Int { metrics.wordCount }
    var characterCount: Int { metrics.characterCount }
    var sentenceCount: Int { metrics.sentenceCount }
    var averageSentenceLength: Double { metrics.averageSentenceLength }
    var paragraphCount: Int { metrics.paragraphCount }
    var vocabularyDiversity: Double { metrics.vocabularyDiversity }
    var averageWordLength: Double { metrics.averageWordLength }
    var readabilityScore: Double { metrics.readabilityScore }
    var readingTime: Double { metrics.readingTime }
    var speakingTime: Double { metrics.speakingTime }
    var writingScore: Int { metrics.writingScore }

    var spellingCount: Int { metrics.issueSummary.spelling }
    var grammarCount: Int { metrics.issueSummary.grammar }
    var clarityCount: Int { metrics.issueSummary.clarity }
    var engagementCount: Int { metrics.issueSummary.engagement }
    var styleCount: Int { metrics.issueSummary.delivery }
    var totalActiveIssueCount: Int { metrics.issueSummary.total }

    func textDidChange(_ newText: String) {
        textDidChange(newText, isProgrammatic: false)
    }

    func textDidChange(_ newText: String, isProgrammatic: Bool) {
        guard newText != text else { return }
        text = newText
        issueGatekeeper.handleTextChange(isProgrammatic: isProgrammatic)
        rebuildMetrics(analysis: cachedAnalysis, issues: issues)
        scheduleCheck()
    }

    func scheduleCheck() {
        checkTask?.cancel()
        checkGeneration &+= 1
        let generation = checkGeneration
        checkTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.2))
            guard !Task.isCancelled else { return }
            await runCheck(generation: generation)
        }
    }

    private nonisolated static func analyzeAndRunRules(
        text: String,
        formality: FormalityLevel,
        audience: AudienceLevel,
        disabledRules: Set<String>
    ) async -> (NLAnalysis, [WritingIssue]) {
        let analysis = NLAnalysisService.analyze(
            text,
            formality: formality,
            audience: audience
        )
        let ruleIssues = RuleRegistry.runAll(
            text: text,
            analysis: analysis,
            disabledRules: disabledRules
        )
        return (analysis, ruleIssues)
    }

    private func resolveSpellIssues(text: String) async -> [WritingIssue] {
        guard !Task.isCancelled else { return [] }
        logger.debug("resolveSpellIssues: passive spell check stays local")
        return await SpellCheckService.check(text: text)
    }

    func runCheck(generation: Int) async {
        guard generation == checkGeneration else { return }
        let currentText = text

        let formality = preferencesManager.formalityLevel
        let audience = preferencesManager.audienceLevel
        let disabledRules = preferencesManager.disabledRules

        async let spellIssues = resolveSpellIssues(text: currentText)
        async let analysisAndRules = Self.analyzeAndRunRules(
            text: currentText,
            formality: formality,
            audience: audience,
            disabledRules: disabledRules
        )

        let (analysis, ruleIssues) = await analysisAndRules
        let detected = await spellIssues + ruleIssues

        guard !Task.isCancelled, generation == checkGeneration else { return }

        cachedAnalysis = analysis

        writingStatsStore.recordWordCount(metrics.wordCount)
        for issue in detected {
            writingStatsStore.recordIssue(type: issue.type)
        }

        let previousIssues = issues
        let visibleIssueIDs = Set(detected.map(\.id))
        correctionApplicator.pruneRecentlyCorrected(keeping: visibleIssueIDs)

        let update = issueGatekeeper.reconcile(
            detectedIssues: detected,
            previousVisibleIssues: previousIssues,
            ignoreStore: ignoreRulesStore,
            recentlyCorrectedIssueIDs: correctionApplicator.recentlyCorrectedIssueIDs,
            allowHUD: correctionApplicator.canShowHUD()
        )

        issues = update.visibleIssues
        unseenIssueIDs = update.unseenIssueIDs
        rebuildMetrics(analysis: analysis, issues: update.visibleIssues)

        if !update.pendingHUDIssues.isEmpty {
            onNewIssuesReadyForHUD?(update.pendingHUDIssues)
        }
    }

    func applyCorrection(_ issue: WritingIssue, correction: String) {
        issues.removeAll { $0.id == issue.id }
        unseenIssueIDs.remove(issue.id)
        rebuildMetrics(analysis: cachedAnalysis, issues: issues)
        correctionApplicator.apply(issue: issue, correction: correction)
    }

    func undoCorrection(original: String, correction: String) {
        correctionApplicator.undo(original: original, correction: correction)
    }

    func replaceSelection(replacement: String) {
        correctionApplicator.replaceSelection(replacement: replacement)
    }

    func ignoreIssue(_ issue: WritingIssue) {
        unseenIssueIDs = issueGatekeeper.ignoreSession(issue)
        issues.removeAll { $0.id == issue.id }
        rebuildMetrics(analysis: cachedAnalysis, issues: issues)
    }

    private func rebuildMetrics(analysis: NLAnalysis?, issues: [WritingIssue]) {
        metrics = DocumentMetrics.build(text: text, analysis: analysis, issues: issues)
    }
}
