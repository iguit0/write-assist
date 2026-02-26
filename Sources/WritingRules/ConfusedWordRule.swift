// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import NaturalLanguage

struct ConfusedWordRule: WritingRule {
    let ruleID = "confusedWord"
    let issueType = IssueType.confusedWord

    private struct ConfusedPair {
        let words: [String]
        let hint: String
    }

    // Codable mirror for JSON decoding (#022)
    private struct JSONPair: Decodable {
        let words: [String]
        let hint: String
    }
    private struct JSONRoot: Decodable {
        let pairs: [JSONPair]
    }

    // Load pairs from Bundle.module JSON; fall back to empty (non-fatal).
    private static let pairs: [ConfusedPair] = {
        guard let url = Bundle.module.url(forResource: "confused-words", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(JSONRoot.self, from: data)
        else { return [] }
        return root.pairs.map { ConfusedPair(words: $0.words, hint: $0.hint) }
    }()

    // Build a lookup: word -> [pairs containing that word]
    private static let wordToPairs: [String: [ConfusedPair]] = {
        var result: [String: [ConfusedPair]] = [:]
        for pair in pairs {
            for word in pair.words {
                result[word.lowercased(), default: []].append(pair)
            }
        }
        return result
    }()

    func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        var issues: [WritingIssue] = []

        for (word, _, range) in analysis.wordPOSTags {
            let lower = word.lowercased()
            guard let matchingPairs = Self.wordToPairs[lower] else { continue }

            for pair in matchingPairs {
                let nsRange = NSRange(range, in: text)
                let alternatives = pair.words.filter { $0.lowercased() != lower }
                issues.append(WritingIssue(
                    type: .confusedWord,
                    ruleID: ruleID,
                    range: nsRange,
                    word: word,
                    message: pair.hint,
                    suggestions: alternatives
                ))
            }
        }

        return issues
    }
}
