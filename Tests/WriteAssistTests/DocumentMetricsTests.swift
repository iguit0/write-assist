// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import Testing
@testable import WriteAssistCore

@Suite("DocumentMetrics")
struct DocumentMetricsTests {
    @Test("empty text yields zeroed metrics and score 100")
    func emptyText() {
        let metrics = DocumentMetrics.build(text: "", analysis: nil, issues: [])
        #expect(metrics.wordCount == 0)
        #expect(metrics.characterCount == 0)
        #expect(metrics.writingScore == 100)
    }

    @Test("issue summary maps by category")
    func issueSummaryCounts() {
        let issues = [
            WritingIssue(type: .spelling, ruleID: "spell", range: NSRange(location: 0, length: 4), word: "teh", message: "", suggestions: []),
            WritingIssue(type: .grammar, ruleID: "grammar", range: NSRange(location: 10, length: 2), word: "is", message: "", suggestions: []),
            WritingIssue(type: .wordiness, ruleID: "wordiness", range: NSRange(location: 20, length: 5), word: "really", message: "", suggestions: []),
        ]

        let metrics = DocumentMetrics.build(text: "teh is really", analysis: nil, issues: issues)
        #expect(metrics.issueSummary.spelling == 1)
        #expect(metrics.issueSummary.grammar == 1)
        #expect(metrics.issueSummary.clarity == 1)
        #expect(metrics.issueSummary.total == 3)
    }
}
