// WriteAssist — macOS menu bar writing assistant
// Copyright © 2024 Igor Alves. All rights reserved.

import Foundation

/// A point-in-time snapshot of the analysis results for a specific document revision.
///
/// Equatable note: `NLAnalysis` contains tuple arrays with `Range<String.Index>` and
/// `NLTag?` which do not conform to `Equatable`, so a custom `==` is provided that
/// compares all fields except `analysis` (which is treated as always equal for
/// diffing purposes — callers should use `documentRevision` / `analyzedAt` to detect
/// staleness instead).
public struct ReviewAnalysisSnapshot: Sendable {
    public let documentID: UUID
    public let documentRevision: Int
    public let analyzedAt: Date
    // analysis, issues, and metrics use internal types — accessible within the module only
    let analysis: NLAnalysis
    public let issues: [WritingIssue]
    public let metrics: DocumentMetrics
    public let paragraphs: [ReviewParagraphSnapshot]

    init(
        documentID: UUID,
        documentRevision: Int,
        analyzedAt: Date,
        analysis: NLAnalysis,
        issues: [WritingIssue],
        metrics: DocumentMetrics,
        paragraphs: [ReviewParagraphSnapshot]
    ) {
        self.documentID = documentID
        self.documentRevision = documentRevision
        self.analyzedAt = analyzedAt
        self.analysis = analysis
        self.issues = issues
        self.metrics = metrics
        self.paragraphs = paragraphs
    }
}

extension ReviewAnalysisSnapshot: Equatable {
    public static func == (lhs: ReviewAnalysisSnapshot, rhs: ReviewAnalysisSnapshot) -> Bool {
        lhs.documentID == rhs.documentID &&
        lhs.documentRevision == rhs.documentRevision &&
        lhs.analyzedAt == rhs.analyzedAt &&
        lhs.metrics == rhs.metrics &&
        lhs.paragraphs == rhs.paragraphs &&
        lhs.issues.map(\.id) == rhs.issues.map(\.id)
        // `analysis` is intentionally excluded: NLAnalysis contains tuple arrays
        // with Range<String.Index> and NLTag? which do not conform to Equatable.
        // Use `documentRevision` or `analyzedAt` to detect snapshot staleness.
    }
}

/// A snapshot of a single paragraph within a `ReviewAnalysisSnapshot`.
///
/// The `id` is always `"\(range.location):\(range.length)"` — a range-based ID
/// contract that is stable across re-analyses of the same document revision.
public struct ReviewParagraphSnapshot: Identifiable, Sendable, Equatable {
    // id is always "\(range.location):\(range.length)" — range-based ID contract
    public let id: String
    public let range: NSRange
    public let text: String
    public let sentences: [ReviewSentenceSnapshot]
    public let issueIDs: [String]

    public init(id: String, range: NSRange, text: String, sentences: [ReviewSentenceSnapshot], issueIDs: [String]) {
        self.id = id
        self.range = range
        self.text = text
        self.sentences = sentences
        self.issueIDs = issueIDs
    }
}

/// A snapshot of a single sentence within a `ReviewParagraphSnapshot`.
///
/// The `id` is always `"\(range.location):\(range.length)"` — a range-based ID
/// contract that is stable across re-analyses of the same document revision.
public struct ReviewSentenceSnapshot: Identifiable, Sendable, Equatable {
    // id is always "\(range.location):\(range.length)" — range-based ID contract
    public let id: String
    public let range: NSRange
    public let text: String
    public let issueIDs: [String]

    public init(id: String, range: NSRange, text: String, issueIDs: [String]) {
        self.id = id
        self.range = range
        self.text = text
        self.issueIDs = issueIDs
    }
}
