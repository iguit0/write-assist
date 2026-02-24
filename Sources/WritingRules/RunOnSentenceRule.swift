// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

struct RunOnSentenceRule: WritingRule {
    let ruleID = "runOnSentence"
    let issueType = IssueType.runOn

    private static let wordThreshold = 40

    func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        var issues: [WritingIssue] = []

        for sentence in analysis.sentences {
            let words = sentence.split(whereSeparator: { $0.isWhitespace })
            guard words.count > Self.wordThreshold else { continue }

            guard let range = text.range(of: sentence) else { continue }
            let nsRange = NSRange(range, in: text)

            let truncated = words.prefix(6).joined(separator: " ") + "..."
            issues.append(WritingIssue(
                type: .runOn,
                range: nsRange,
                word: truncated,
                message: "This sentence has \(words.count) words — consider breaking it up",
                suggestions: []
            ))
        }

        return issues
    }
}
