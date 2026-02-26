// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

struct CapitalizationRule: WritingRule {
    let ruleID = "capitalization"
    let issueType = IssueType.capitalization

    // Known identifiers that legitimately start with a lowercase letter (#040)
    private static let legitimateLowercaseStarts: Set<String> = [
        "macOS", "iOS", "iPadOS", "watchOS", "tvOS", "visionOS",
        "iCloud", "iPhone", "iPad", "iMac", "HomePod"
    ]

    // Characters that indicate a code token, file path, or URL (#040)
    private static let codeIndicatorChars: Set<Character> = ["/", ".", "_", "(", ")", "="]

    func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        var issues: [WritingIssue] = []

        for (sentence, sentenceRange) in analysis.sentenceRanges {
            let nsRange = NSRange(sentenceRange, in: text)

            // Skip sentences that start with a number or symbol
            guard let firstChar = sentence.first, firstChar.isLetter else { continue }
            guard firstChar.isLowercase else { continue }

            // Extract the first whitespace-delimited word for heuristic checks (#040)
            let firstWord = sentence.components(separatedBy: .whitespaces).first ?? ""

            // Skip single-character tokens (abbreviations like "e.g.", "i.e.")
            guard firstWord.count > 1 else { continue }

            // Skip code tokens and file paths (contain /, ., _, (, ), = or start with ~)
            guard !firstWord.contains(where: { Self.codeIndicatorChars.contains($0) }),
                  !firstWord.hasPrefix("~") else { continue }

            // Skip known lowercase-start brand names and platform identifiers
            guard !Self.legitimateLowercaseStarts.contains(firstWord) else { continue }

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

        return issues
    }
}
