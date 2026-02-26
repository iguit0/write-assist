// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

struct WordinessRule: WritingRule {
    let ruleID = "wordiness"
    let issueType = IssueType.wordiness

    private static let wordyPhrases: [(phrase: String, replacement: String)] = [
        ("due to the fact that", "because"),
        ("in order to", "to"),
        ("at this point in time", "now"),
        ("in the event that", "if"),
        ("for the purpose of", "to"),
        ("with regard to", "about"),
        ("with respect to", "about"),
        ("in spite of the fact that", "although"),
        ("in light of the fact that", "because"),
        ("on account of the fact that", "because"),
        ("it is important to note that", "notably"),
        ("it should be noted that", "note that"),
        ("the fact that", "that"),
        ("has the ability to", "can"),
        ("is able to", "can"),
        ("in a position to", "can"),
        ("at the present time", "now"),
        ("at this time", "now"),
        ("by means of", "by"),
        ("in the process of", "while"),
        ("in the near future", "soon"),
        ("a large number of", "many"),
        ("a majority of", "most"),
        ("a number of", "several"),
        ("in the amount of", "for"),
        ("on a daily basis", "daily"),
        ("on a regular basis", "regularly"),
        ("on a weekly basis", "weekly"),
        ("take into consideration", "consider"),
        ("make a decision", "decide"),
        ("come to a conclusion", "conclude"),
        ("give an indication of", "indicate"),
        ("make an adjustment to", "adjust"),
        ("have a tendency to", "tend to"),
        ("put emphasis on", "emphasize"),
        ("is indicative of", "indicates"),
        ("is reflective of", "reflects"),
        ("in close proximity to", "near"),
        ("in my opinion I think", "I think"),
        ("despite the fact that", "although"),
        ("during the course of", "during"),
        ("each and every one", "each"),
        ("first of all", "first"),
        ("for all intents and purposes", "effectively"),
        ("has the capacity to", "can"),
        ("in the absence of", "without"),
        ("it goes without saying", "clearly"),
        ("it is necessary that", "must"),
        ("it is worth noting that", "note that"),
        ("needless to say", "clearly"),
        ("of the opinion that", "think"),
        ("owing to the fact that", "because"),
        ("prior to the start of", "before"),
        ("subsequent to", "after"),
        ("the manner in which", "how"),
        ("the reason being that", "because"),
        ("until such time as", "until"),
        ("with the exception of", "except"),
        ("as a matter of fact", "in fact"),
        ("as a consequence of", "because of"),
        ("as far as I'm concerned", "I think"),
        ("at the end of the day", "ultimately"),
        ("be that as it may", "regardless"),
        ("by and large", "generally"),
        ("for what it's worth", ""),
        ("in addition to the above", "also"),
        ("in any case", "regardless"),
        ("in other words", ""),
        ("in terms of", "regarding"),
        ("in this day and age", "today"),
        ("it stands to reason that", "therefore"),
        ("last but not least", "finally"),
        ("more often than not", "usually"),
        ("the bottom line is", "ultimately"),
        ("the point I am trying to make", "my point"),
        ("what I mean to say is", ""),
        ("when all is said and done", "ultimately"),
    ]

    func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        let lower = text.lowercased()
        let nsText = text as NSString
        var issues: [WritingIssue] = []

        for (phrase, replacement) in Self.wordyPhrases {
            var searchStart = lower.startIndex
            while let range = lower.range(of: phrase, range: searchStart..<lower.endIndex) {
                let nsRange = NSRange(range, in: text)
                guard nsRange.location + nsRange.length <= nsText.length else { break }

                // Word boundary check — avoids matching inside larger words
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
                    let suggestions = replacement.isEmpty ? [] : [replacement]
                    issues.append(WritingIssue(
                        type: .wordiness,
                        ruleID: ruleID,
                        range: nsRange,
                        word: word,
                        message: replacement.isEmpty
                            ? "Wordy phrase — consider removing"
                            : "Wordy phrase — consider \"\(replacement)\"",
                        suggestions: suggestions
                    ))
                }

                searchStart = range.upperBound
            }
        }

        return issues
    }
}
