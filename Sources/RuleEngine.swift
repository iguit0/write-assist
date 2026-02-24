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
        let prefs = PreferencesManager.shared
        var issues: [WritingIssue] = []
        for rule in allRules {
            guard prefs.isRuleEnabled(rule.ruleID) else { continue }
            issues.append(contentsOf: rule.check(text: text, analysis: analysis))
        }
        return issues
    }
}
