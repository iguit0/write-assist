// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import NaturalLanguage

struct SentenceFragmentRule: WritingRule {
    let ruleID = "sentenceFragment"
    let issueType = IssueType.fragment

    private static let minWordsForCheck = 3

    func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        var issues: [WritingIssue] = []

        for sentence in analysis.sentences {
            let wordCount = sentence.split(whereSeparator: { $0.isWhitespace }).count
            guard wordCount >= Self.minWordsForCheck else { continue }

            // Tag this individual sentence for POS
            let tagger = NLTagger(tagSchemes: [.lexicalClass])
            tagger.string = sentence
            var hasVerb = false
            tagger.enumerateTags(
                in: sentence.startIndex..<sentence.endIndex,
                unit: .word,
                scheme: .lexicalClass,
                options: [.omitWhitespace, .omitPunctuation]
            ) { tag, _ in
                if tag == .verb {
                    hasVerb = true
                    return false
                }
                return true
            }

            if !hasVerb {
                guard let range = text.range(of: sentence) else { continue }
                let nsRange = NSRange(range, in: text)
                let truncated: String
                if sentence.count > 30 {
                    truncated = String(sentence.prefix(27)) + "..."
                } else {
                    truncated = sentence
                }

                issues.append(WritingIssue(
                    type: .fragment,
                    range: nsRange,
                    word: truncated,
                    message: "Sentence fragment — may be missing a verb",
                    suggestions: []
                ))
            }
        }

        return issues
    }
}
