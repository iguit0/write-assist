// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

struct CapitalizationRule: WritingRule {
    let ruleID = "capitalization"
    let issueType = IssueType.capitalization

    func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        var issues: [WritingIssue] = []

        for (sentence, sentenceRange) in analysis.sentenceRanges {
            let nsRange = NSRange(sentenceRange, in: text)

            // Skip sentences that start with a number or symbol
            guard let firstChar = sentence.first, firstChar.isLetter else { continue }

            if firstChar.isLowercase {
                let corrected = sentence.prefix(1).uppercased() + sentence.dropFirst()
                issues.append(WritingIssue(
                    type: .capitalization,
                    ruleID: ruleID,
                    range: NSRange(location: nsRange.location, length: 1),
                    word: String(firstChar),
                    message: "Sentence should start with a capital letter",
                    suggestions: [String(corrected.prefix(1))]
                ))
            }
        }

        return issues
    }
}
