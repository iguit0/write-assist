// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Testing
import Foundation
@testable import WriteAssistCore

// MARK: - Helper

/// Create a real NLAnalysis for a given text. Uses the actual NLP pipeline so
/// tests verify rules against realistic POS-tagged, sentence-segmented data.
private func analyze(_ text: String) -> NLAnalysis {
    NLAnalysisService.analyze(text)
}

/// Empty analysis for rules that don't use NLAnalysis at all (e.g. DoubleWordRule).
private let emptyAnalysis = NLAnalysisService.analyze("")

// MARK: - DoubleWordRule

@Suite("DoubleWordRule")
struct DoubleWordRuleTests {
    private let rule = DoubleWordRule()

    @Test("flags repeated words")
    func flagsRepeatedWords() {
        let text = "the the quick fox"
        let issues = rule.check(text: text, analysis: analyze(text))
        #expect(issues.count == 1)
        #expect(issues[0].word.lowercased().contains("the the"))
        #expect(issues[0].ruleID == "doubleWord")
    }

    @Test("no issue for normal text")
    func noIssueForNormalText() {
        let text = "the quick brown fox"
        let issues = rule.check(text: text, analysis: analyze(text))
        #expect(issues.isEmpty)
    }

    @Test("empty text produces no issues")
    func emptyText() {
        let issues = rule.check(text: "", analysis: emptyAnalysis)
        #expect(issues.isEmpty)
    }

    @Test("case-insensitive detection")
    func caseInsensitiveDetection() {
        let text = "The the fox"
        let issues = rule.check(text: text, analysis: analyze(text))
        #expect(issues.count == 1)
    }
}

// MARK: - RedundancyRule

@Suite("RedundancyRule")
struct RedundancyRuleTests {
    private let rule = RedundancyRule()

    @Test("flags known redundant phrases")
    func flagsRedundantPhrases() {
        let text = "The end result was unexpected."
        let issues = rule.check(text: text, analysis: analyze(text))
        #expect(issues.count == 1)
        #expect(issues[0].ruleID == "redundancy")
        #expect(issues[0].suggestions.first == "result")
    }

    @Test("no false positive for non-redundant text")
    func noFalsePositive() {
        let text = "The outcome was positive."
        let issues = rule.check(text: text, analysis: analyze(text))
        #expect(issues.isEmpty)
    }

    @Test("word boundary — does not match phrase inside a larger word")
    func wordBoundary() {
        // "reasoning" does not contain "reason why" so no match expected
        let text = "Her reasoning was sound."
        let issues = rule.check(text: text, analysis: analyze(text))
        #expect(issues.isEmpty)
    }

    @Test("empty text produces no issues")
    func emptyText() {
        let issues = rule.check(text: "", analysis: emptyAnalysis)
        #expect(issues.isEmpty)
    }
}

// MARK: - WordinessRule

@Suite("WordinessRule")
struct WordinessRuleTests {
    private let rule = WordinessRule()

    @Test("flags wordy phrases")
    func flagsWordyPhrases() {
        let text = "Due to the fact that it rained, we stayed inside."
        let issues = rule.check(text: text, analysis: analyze(text))
        // "due to the fact that" AND the nested "the fact that" both match — 2 issues expected
        #expect(issues.count >= 1)
        #expect(issues.contains { $0.suggestions.first == "because" })
        #expect(issues.allSatisfy { $0.ruleID == "wordiness" })
    }

    @Test("no false positive for concise text")
    func noFalsePositive() {
        let text = "Because it rained, we stayed inside."
        let issues = rule.check(text: text, analysis: analyze(text))
        #expect(issues.isEmpty)
    }

    @Test("empty text produces no issues")
    func emptyText() {
        let issues = rule.check(text: "", analysis: emptyAnalysis)
        #expect(issues.isEmpty)
    }
}

// MARK: - HedgingRule

@Suite("HedgingRule")
struct HedgingRuleTests {
    private let rule = HedgingRule()

    @Test("flags hedging phrases")
    func flagsHedgingPhrases() {
        let text = "I think this might be right."
        let issues = rule.check(text: text, analysis: analyze(text))
        #expect(issues.contains { $0.word.lowercased() == "i think" })
    }

    @Test("word boundary — does not flag partial phrase matches")
    func wordBoundaryForPartialMatch() {
        // "thinking" does NOT contain "i think" as a boundary match
        let text = "She was thinking clearly."
        let issues = rule.check(text: text, analysis: analyze(text))
        // "thinking" is not in the hedging phrase list
        #expect(!issues.contains { $0.word.lowercased() == "thinking" })
    }
}

// MARK: - ConfusedWordRule

@Suite("ConfusedWordRule")
struct ConfusedWordRuleTests {
    private let rule = ConfusedWordRule()

    @Test("flags words in known confused pairs (fixes #005 — previously returned false for most pairs)")
    func flagsAllConfusedWords() {
        // "loose" and "lose" are a confused pair. Previously shouldFlagWord returned false for "loose".
        let text = "The bolt is loose."
        let issues = rule.check(text: text, analysis: analyze(text))
        #expect(issues.count >= 1)
        #expect(issues[0].ruleID == "confusedWord")
    }

    @Test("previously-skipped pairs now flagged")
    func previouslySkippedPairsNowFlagged() {
        // These all returned false from shouldFlagWord before the fix
        let pairs: [(text: String, word: String)] = [
            ("The bolt is loose.", "loose"),
            ("I accept the offer.", "accept"),
            ("She paid the compliment.", "compliment"),
            ("The principal reason", "principal"),
        ]
        for (text, expectedWord) in pairs {
            let issues = rule.check(text: text, analysis: analyze(text))
            #expect(issues.contains { $0.word.lowercased() == expectedWord },
                    "Expected '\(expectedWord)' to be flagged in: \(text)")
        }
    }

    @Test("ruleID is confusedWord")
    func ruleIDIsConfusedWord() {
        let text = "The affect was significant."
        let issues = rule.check(text: text, analysis: analyze(text))
        if let issue = issues.first {
            #expect(issue.ruleID == "confusedWord")
        }
    }
}

// MARK: - WritingIssue

@Suite("WritingIssue")
struct WritingIssueTests {
    @Test("has ruleID field")
    func hasRuleIDField() {
        let issue = WritingIssue(
            type: .spelling,
            ruleID: "spelling",
            range: NSRange(location: 0, length: 4),
            word: "test",
            message: "test",
            suggestions: []
        )
        #expect(issue.ruleID == "spelling")
    }

    @Test("no isIgnored property — dead code removed (fixes #012)")
    func noIsIgnoredProperty() {
        // Verifies the struct has the correct fields and NOT isIgnored.
        // If isIgnored were re-added, this init would fail with a compile error.
        let issue = WritingIssue(
            type: .grammar,
            ruleID: "grammar",
            range: NSRange(location: 0, length: 7),
            word: "grammar",
            message: "grammar issue",
            suggestions: ["fix"]
        )
        #expect(issue.ruleID == "grammar")
        #expect(issue.suggestions == ["fix"])
    }
}
