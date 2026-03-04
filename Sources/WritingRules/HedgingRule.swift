// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

struct HedgingRule: WritingRule {
    let ruleID = "hedging"
    let issueType = IssueType.hedging

    /// High-signal hedging phrases — specific constructions that unambiguously weaken writing.
    /// Flagging these rarely produces false positives.
    private static let highSignalPhrases: [String] = [
        "i think", "i believe", "i feel like", "i guess", "i suppose",
        "maybe", "perhaps", "possibly", "probably", "seemingly",
        "sort of", "kind of", "a little bit",
        "it seems", "it appears", "it might", "it could be",
        "to some extent", "in some ways",
        "more or less", "somewhat",
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

    private static let lowSignalPhrases: [String] = [
        "just", "basically", "actually", "really", "honestly"
    ]

    func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        let lower = text.lowercased()
        let nsText = text as NSString
        var issues: [WritingIssue] = []

        for phrase in Self.highSignalPhrases {
            var searchStart = lower.startIndex
            while let range = lower.range(of: phrase, range: searchStart..<lower.endIndex) {
                guard isWordBounded(range, in: lower) else {
                    searchStart = range.upperBound
                    continue
                }
                let nsRange = NSRange(range, in: text)
                guard nsRange.location + nsRange.length <= nsText.length else { break }
                let word = nsText.substring(with: nsRange)
                issues.append(WritingIssue(
                    type: .hedging,
                    ruleID: ruleID,
                    range: nsRange,
                    word: word,
                    message: "Hedging language weakens your writing",
                    suggestions: []
                ))

                searchStart = range.upperBound
            }
        }

        for phrase in Self.lowSignalPhrases {
            var searchStart = lower.startIndex
            while let range = lower.range(of: phrase, range: searchStart..<lower.endIndex) {
                let nsRange = NSRange(range, in: text)
                guard nsRange.location + nsRange.length <= nsText.length else { break }
                guard isWordBounded(range, in: lower),
                      shouldFlagLowSignal(range: range, lower: lower, nsText: nsText, phrase: phrase) else {
                    searchStart = range.upperBound
                    continue
                }
                let word = nsText.substring(with: nsRange)
                issues.append(WritingIssue(
                    type: .hedging,
                    ruleID: ruleID,
                    range: nsRange,
                    word: word,
                    message: "Hedging language weakens your writing",
                    suggestions: []
                ))

                searchStart = range.upperBound
            }
        }

        return issues
    }

    private func shouldFlagLowSignal(
        range: Range<String.Index>,
        lower: String,
        nsText: NSString,
        phrase: String
    ) -> Bool {
        if isSentenceStart(range: range, lower: lower) {
            return true
        }
        let nsRange = NSRange(range, in: lower)
        let paragraphRange = nsText.paragraphRange(for: nsRange)
        let paragraph = (lower as NSString).substring(with: paragraphRange)
        return countOccurrencesWordBounded(of: phrase, in: paragraph) > 1
    }

    private func isSentenceStart(range: Range<String.Index>, lower: String) -> Bool {
        var index = range.lowerBound
        while index > lower.startIndex {
            index = lower.index(before: index)
            let char = lower[index]
            if char.isWhitespace {
                continue
            }
            return char == "." || char == "!" || char == "?" || char == "\n"
        }
        return true
    }

    private func countOccurrencesWordBounded(of phrase: String, in text: String) -> Int {
        let lower = text.lowercased()
        var count = 0
        var searchStart = lower.startIndex
        while let found = lower.range(of: phrase, range: searchStart..<lower.endIndex) {
            if isWordBounded(found, in: lower) {
                count += 1
            }
            searchStart = found.upperBound
        }
        return count
    }
}
