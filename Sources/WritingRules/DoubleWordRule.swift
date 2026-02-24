// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

struct DoubleWordRule: WritingRule {
    let ruleID = "doubleWord"
    let issueType = IssueType.doubleWord

    // Matches a word repeated with whitespace between (e.g., "the the")
    private static let pattern = try! NSRegularExpression(
        pattern: #"\b(\w+)\s+\1\b"#,
        options: [.caseInsensitive]
    )

    func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = Self.pattern.matches(in: text, range: fullRange)

        return matches.compactMap { match in
            guard match.range.location + match.range.length <= nsText.length else { return nil }
            let duplicated = nsText.substring(with: match.range)
            let firstWordRange = match.range(at: 1)
            guard firstWordRange.location != NSNotFound else { return nil }
            let singleWord = nsText.substring(with: firstWordRange)

            return WritingIssue(
                type: .doubleWord,
                range: match.range,
                word: duplicated,
                message: "Repeated word: \"\(singleWord)\"",
                suggestions: [singleWord]
            )
        }
    }
}
