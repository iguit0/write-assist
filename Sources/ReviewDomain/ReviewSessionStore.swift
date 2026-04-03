// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import OSLog

@MainActor
@Observable
public final class ReviewSessionStore {

    // MARK: - Document state

    public var document: ReviewDocument
    public var analysisState: ReviewAnalysisState = .idle
    public var selectedIssueID: String?
    public var selectedParagraphID: String?
    public var selectedSentenceID: String?
    public var selectedEditorRange: NSRange?

    // MARK: - Dependencies

    private let engine: any ReviewEngine
    private var reviewTask: Task<Void, Never>?
    private var reviewGeneration = 0

    // MARK: - Logging

    private let logger = Logger(subsystem: "com.writeassist", category: "ReviewSessionStore")

    // MARK: - Init

    public init() {
        self.engine = DeterministicReviewEngine()
        self.document = ReviewDocument(
            id: UUID(),
            text: "",
            source: .manual,
            revision: 0,
            updatedAt: Date()
        )
    }

    /// Internal initialiser for testing and dependency injection.
    init(engine: any ReviewEngine) {
        self.engine = engine
        self.document = ReviewDocument(
            id: UUID(),
            text: "",
            source: .manual,
            revision: 0,
            updatedAt: Date()
        )
    }

    // MARK: - Document mutation (the ONLY path for changing text)

    /// Replace the entire document text, optionally triggering a re-review.
    public func replaceText(
        _ newText: String,
        source: ReviewDocumentSource = .manual,
        trigger: ReviewTrigger = .editorChange,
        autoReview: Bool = false
    ) {
        document = ReviewDocument(
            id: document.id,
            text: newText,
            source: source,
            revision: document.revision + 1,
            updatedAt: Date()
        )
        analysisState = .idle
        if autoReview && !newText.isEmpty {
            requestReview(trigger: trigger)
        }
    }

    /// Apply a local in-place replacement within the current document text.
    public func applyReplacement(
        range: NSRange,
        replacement: String,
        trigger: ReviewTrigger = .rewriteApplied
    ) {
        guard let swiftRange = Range(range, in: document.text) else { return }
        var mutableText = document.text
        mutableText.replaceSubrange(swiftRange, with: replacement)
        replaceText(mutableText, trigger: trigger, autoReview: true)
    }

    // MARK: - Review lifecycle

    public func requestReview(trigger: ReviewTrigger = .manualReview) {
        guard !document.text.isEmpty else {
            analysisState = .idle
            return
        }
        reviewTask?.cancel()
        reviewGeneration += 1
        let generation = reviewGeneration
        let capturedDocument = document
        // Preferences snapshot — Phase 2 uses neutral defaults.
        // Phase 3 will inject real PreferencesManager values.
        let preferences = ReviewPreferencesSnapshot(
            formality: .neutral,
            audience: .general,
            disabledRules: []
        )
        analysisState = .analyzing(revision: capturedDocument.revision)
        logger.info("Review requested — trigger: \(String(describing: trigger)), generation: \(generation), revision: \(capturedDocument.revision)")
        // Task (not Task.detached) — inherits @MainActor isolation; staleness guard MUST run on MainActor.
        reviewTask = Task {
            let snapshot = await engine.analyze(
                document: capturedDocument,
                preferences: preferences
            )
            // Reject stale results
            guard !Task.isCancelled,
                  generation == self.reviewGeneration,
                  snapshot.documentRevision == self.document.revision else {
                self.logger.debug("Review result discarded — stale generation or revision mismatch (generation: \(generation), current: \(self.reviewGeneration))")
                return
            }
            // Fill in paragraph grouping
            let grouped = ReviewGrouping.group(
                text: capturedDocument.text,
                analysis: snapshot.analysis,
                issues: snapshot.issues
            )
            let complete = ReviewAnalysisSnapshot(
                documentID: snapshot.documentID,
                documentRevision: snapshot.documentRevision,
                analyzedAt: snapshot.analyzedAt,
                analysis: snapshot.analysis,
                issues: snapshot.issues,
                metrics: snapshot.metrics,
                paragraphs: grouped
            )
            self.analysisState = .ready(complete)
            self.logger.info("Review complete — revision: \(snapshot.documentRevision), issues: \(snapshot.issues.count), paragraphs: \(grouped.count)")
        }
    }

    public func cancelReview() {
        reviewTask?.cancel()
        reviewTask = nil
        if case .analyzing = analysisState {
            analysisState = .idle
        }
        logger.info("Review cancelled")
    }

    // MARK: - Selection

    public func selectIssue(id: String?) {
        selectedIssueID = id
    }

    public func selectParagraph(id: String?) {
        selectedParagraphID = id
        selectedSentenceID = nil
        selectedIssueID = nil
    }

    public func selectSentence(id: String?) {
        selectedSentenceID = id
        selectedIssueID = nil
    }

    public func ignoreIssue(id: String) {
        // Phase 3 stub: deselect the issue.
        // Real ignore/suppression storage comes in a later phase.
        if selectedIssueID == id { selectedIssueID = nil }
    }
}

public enum ReviewAnalysisState: Sendable, Equatable {
    case idle
    case analyzing(revision: Int)
    case ready(ReviewAnalysisSnapshot)
}

public enum ReviewTrigger: Sendable, Equatable {
    case manualReview
    case editorChange
    case importedSelection
    case rewriteApplied
}
