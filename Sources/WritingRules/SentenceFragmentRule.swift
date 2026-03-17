// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

struct SentenceFragmentRule: WritingRule {
    let ruleID = "sentenceFragment"
    let issueType = IssueType.fragment

    private static let minWordsForCheck = 3

    func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        var issues: [WritingIssue] = []
        let tags = analysis.wordPOSTags
        var nextTagIndex = 0

        for (sentence, sentenceRange) in analysis.sentenceRanges {
            while nextTagIndex < tags.count,
                  tags[nextTagIndex].range.upperBound <= sentenceRange.lowerBound {
                nextTagIndex += 1
            }

            var wordCount = 0
            var hasVerb = false

            var tagIndex = nextTagIndex
            while tagIndex < tags.count,
                  tags[tagIndex].range.lowerBound < sentenceRange.upperBound {
                wordCount += 1
                if tags[tagIndex].tag == .verb {
                    hasVerb = true
                }
                tagIndex += 1
            }

            nextTagIndex = tagIndex

            guard wordCount >= Self.minWordsForCheck, !hasVerb else { continue }

            let nsRange = NSRange(sentenceRange, in: text)
            let truncated: String
            if sentence.count > 30 {
                truncated = String(sentence.prefix(27)) + "..."
            } else {
                truncated = sentence
            }

            issues.append(WritingIssue(
                type: .fragment,
                ruleID: ruleID,
                range: nsRange,
                word: truncated,
                message: "Sentence fragment — may be missing a verb",
                suggestions: []
            ))
        }

        return issues
    }
}
