// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

struct InclusiveLanguageRule: WritingRule {
    let ruleID = "inclusiveLanguage"
    let issueType = IssueType.inclusiveLanguage

    // Codable mirror for JSON decoding (#022)
    private struct JSONTerm: Decodable {
        let term: String
        let suggestion: String
    }
    private struct JSONRoot: Decodable {
        let terms: [JSONTerm]
    }

    // Load terms from Bundle.module JSON; fall back to empty (non-fatal).
    private static let terms: [(term: String, suggestion: String)] = {
        guard let url = Bundle.module.url(forResource: "inclusive-language", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(JSONRoot.self, from: data)
        else { return [] }
        return root.terms.map { (term: $0.term, suggestion: $0.suggestion) }
    }()

    func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        let lower = text.lowercased()
        let nsText = text as NSString
        var issues: [WritingIssue] = []

        for (term, suggestion) in Self.terms {
            var searchStart = lower.startIndex
            while let range = lower.range(of: term, range: searchStart..<lower.endIndex) {
                let nsRange = NSRange(range, in: text)
                guard nsRange.location + nsRange.length <= nsText.length else { break }

                // Word boundary check
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
                        type: .inclusiveLanguage,
                        ruleID: ruleID,
                        range: nsRange,
                        word: word,
                        message: "Consider more inclusive language — try \"\(suggestion)\"",
                        suggestions: [suggestion]
                    ))
                }

                searchStart = range.upperBound
            }
        }

        return issues
    }
}
