// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

struct HedgingRule: WritingRule {
    let ruleID = "hedging"
    let issueType = IssueType.hedging

    private static let hedgingPhrases: [String] = [
        "i think", "i believe", "i feel", "i guess", "i suppose",
        "maybe", "perhaps", "possibly", "probably", "seemingly",
        "sort of", "kind of", "a little bit", "a bit",
        "it seems", "it appears", "it might", "it could be",
        "to some extent", "in some ways", "in a way",
        "more or less", "fairly", "rather", "somewhat",
        "just", "basically", "actually", "really",
        "tend to", "tends to", "might be", "could be",
        "it is possible that", "there is a chance that",
        "in my opinion", "from my perspective",
        "generally speaking", "for the most part",
        "to be honest", "to tell the truth",
        "as far as i know", "as far as i can tell",
        "not entirely", "not completely", "not exactly",
        "if you ask me", "if i'm not mistaken",
        "i would say", "i would argue", "i would suggest",
    ]

    func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        let lower = text.lowercased()
        let nsText = text as NSString
        var issues: [WritingIssue] = []

        for phrase in Self.hedgingPhrases {
            var searchStart = lower.startIndex
            while let range = lower.range(of: phrase, range: searchStart..<lower.endIndex) {
                let nsRange = NSRange(range, in: text)
                guard nsRange.location + nsRange.length <= nsText.length else { break }

                // Check word boundaries
                let before = range.lowerBound > lower.startIndex
                    ? lower[lower.index(before: range.lowerBound)]
                    : nil
                let after = range.upperBound < lower.endIndex
                    ? lower[range.upperBound]
                    : nil

                let isWordBounded = (before == nil || !before!.isLetter)
                    && (after == nil || !after!.isLetter)

                if isWordBounded {
                    let word = nsText.substring(with: nsRange)
                    issues.append(WritingIssue(
                        type: .hedging,
                        range: nsRange,
                        word: word,
                        message: "Hedging language weakens your writing",
                        suggestions: []
                    ))
                }

                searchStart = range.upperBound
            }
        }

        return issues
    }
}
