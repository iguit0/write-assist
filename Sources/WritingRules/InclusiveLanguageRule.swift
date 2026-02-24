// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

struct InclusiveLanguageRule: WritingRule {
    let ruleID = "inclusiveLanguage"
    let issueType = IssueType.inclusiveLanguage

    private static let terms: [(term: String, suggestion: String)] = [
        ("mankind", "humankind"), ("manmade", "artificial"), ("man-made", "artificial"),
        ("chairman", "chairperson"), ("manpower", "workforce"),
        ("policeman", "police officer"), ("fireman", "firefighter"),
        ("mailman", "mail carrier"), ("stewardess", "flight attendant"),
        ("businessman", "businessperson"), ("spokesman", "spokesperson"),
        ("congressman", "congressperson"), ("cameraman", "camera operator"),
        ("foreman", "supervisor"), ("salesman", "salesperson"),
        ("workman", "worker"), ("craftsman", "craftsperson"),
        ("layman", "layperson"), ("middleman", "intermediary"),
        ("freshman", "first-year student"), ("housewife", "homemaker"),
        ("cleaning lady", "cleaner"), ("master", "primary"), ("slave", "secondary"),
        ("blacklist", "blocklist"), ("whitelist", "allowlist"),
        ("grandfathered", "legacy"), ("man hours", "person hours"),
        ("man-hours", "person-hours"), ("manhole", "maintenance hole"),
        ("handicapped", "person with a disability"),
        ("wheelchair-bound", "wheelchair user"), ("wheelchair bound", "wheelchair user"),
        ("tone deaf", "insensitive"), ("tone-deaf", "insensitive"),
        ("retarded", "delayed"), ("gypped", "cheated"),
        ("eskimo", "Inuit"), ("oriental", "Asian"),
        ("spirit animal", "inspiration"), ("sanity check", "confidence check"),
        ("dummy", "placeholder"), ("blind spot", "oversight"),
        ("manned", "staffed"), ("unmanned", "uncrewed"),
        ("the elderly", "older adults"), ("senior citizen", "older adult"),
        ("suffers from", "lives with"), ("afflicted with", "has"),
        ("victim of", "person who experienced"), ("confined to", "uses"),
        ("able-bodied", "nondisabled"), ("illegal alien", "undocumented person"),
        ("illegal immigrant", "undocumented immigrant"),
        ("guys", "everyone"), ("ladies and gentlemen", "everyone"),
        ("man up", "be brave"), ("waitress", "server"), ("waiter", "server"),
        ("actress", "actor"),
    ]

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
