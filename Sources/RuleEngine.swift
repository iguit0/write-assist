// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

protocol WritingRule: Sendable {
    var ruleID: String { get }
    var issueType: IssueType { get }
    func check(text: String, analysis: NLAnalysis) -> [WritingIssue]
}

enum RuleRegistry {
    static let allRules: [any WritingRule] = [
        // Phase 1
        DoubleWordRule(),
        CapitalizationRule(),
        HedgingRule(),
        RedundancyRule(),
        RunOnSentenceRule(),
        PassiveVoiceRule(),
        WordinessRule(),
        SentenceFragmentRule(),
        // Phase 2
        FormalityRule(),
        InclusiveLanguageRule(),
        ConfusedWordRule(),
    ]

    @MainActor
    static func runAll(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        runAll(text: text, analysis: analysis, disabledRules: PreferencesManager.shared.disabledRules)
    }

    /// Nonisolated overload for use from `Task.detached`. Accepts a pre-snapshotted
    /// `disabledRules` set so it does not need to touch `@MainActor` PreferencesManager.
    nonisolated static func runAll(
        text: String,
        analysis: NLAnalysis,
        disabledRules: Set<String>
    ) -> [WritingIssue] {
        var issues: [WritingIssue] = []
        for rule in allRules {
            guard !disabledRules.contains(rule.ruleID) else { continue }
            issues.append(contentsOf: rule.check(text: text, analysis: analysis))
        }
        return issues
    }
}

// MARK: - Shared Helpers

extension WritingRule {
    /// Returns true if `range` in `text` is bounded by non-letter characters
    /// (or is at the start/end of the string). Prevents matching phrases
    /// inside larger words (e.g., "use" inside "refuse").
    func isWordBounded(_ range: Range<String.Index>, in text: String) -> Bool {
        let before: Character? = range.lowerBound > text.startIndex
            ? text[text.index(before: range.lowerBound)]
            : nil
        let after: Character? = range.upperBound < text.endIndex
            ? text[range.upperBound]
            : nil
        return (before == nil || !before!.isLetter)
            && (after == nil || !after!.isLetter)
    }
}
