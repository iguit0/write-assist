// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

struct RedundancyRule: WritingRule {
    let ruleID = "redundancy"
    let issueType = IssueType.redundancy

    private static let redundantPhrases: [(phrase: String, replacement: String)] = [
        ("very unique", "unique"),
        ("absolutely essential", "essential"),
        ("completely finished", "finished"),
        ("end result", "result"),
        ("free gift", "gift"),
        ("past history", "history"),
        ("true fact", "fact"),
        ("unexpected surprise", "surprise"),
        ("advance planning", "planning"),
        ("added bonus", "bonus"),
        ("basic fundamentals", "fundamentals"),
        ("brief summary", "summary"),
        ("close proximity", "proximity"),
        ("combine together", "combine"),
        ("each and every", "each"),
        ("exactly the same", "the same"),
        ("final outcome", "outcome"),
        ("first and foremost", "first"),
        ("future plans", "plans"),
        ("general consensus", "consensus"),
        ("joint collaboration", "collaboration"),
        ("new innovation", "innovation"),
        ("over exaggerate", "exaggerate"),
        ("past experience", "experience"),
        ("personal opinion", "opinion"),
        ("plan ahead", "plan"),
        ("postpone until later", "postpone"),
        ("reason why", "reason"),
        ("refer back", "refer"),
        ("repeat again", "repeat"),
        ("revert back", "revert"),
        ("still remains", "remains"),
        ("surrounded on all sides", "surrounded"),
        ("terrible tragedy", "tragedy"),
        ("totally destroyed", "destroyed"),
        ("warn in advance", "warn"),
        ("whether or not", "whether"),
        ("completely eliminate", "eliminate"),
        ("currently existing", "existing"),
        ("completely full", "full"),
        ("empty void", "void"),
        ("entirely whole", "whole"),
        ("exact same", "same"),
        ("fellow colleagues", "colleagues"),
        ("final completion", "completion"),
        ("foreign imports", "imports"),
        ("frozen solid", "frozen"),
        ("gather together", "gather"),
        ("grow in size", "grow"),
        ("introduced a new", "introduced"),
        ("knowledgeable expert", "expert"),
        ("major breakthrough", "breakthrough"),
        ("merge together", "merge"),
        ("mutual cooperation", "cooperation"),
        ("never before", "never"),
        ("new beginning", "beginning"),
        ("old adage", "adage"),
        ("open up", "open"),
        ("originally created", "created"),
        ("overused cliché", "cliché"),
        ("past memories", "memories"),
        ("period of time", "period"),
        ("pick and choose", "choose"),
        ("PIN number", "PIN"),
        ("pre-plan", "plan"),
        ("raise up", "raise"),
        ("regular routine", "routine"),
        ("safe haven", "haven"),
        ("same identical", "identical"),
        ("sharp point", "point"),
        ("shiny new", "new"),
        ("sink down", "sink"),
        ("small in size", "small"),
        ("start off", "start"),
        ("still persists", "persists"),
        ("sum total", "total"),
        ("temper tantrum", "tantrum"),
        ("time period", "period"),
        ("total annihilation", "annihilation"),
        ("truly sincere", "sincere"),
        ("twelve noon", "noon"),
        ("twelve midnight", "midnight"),
        ("unintended mistake", "mistake"),
        ("usual custom", "custom"),
        ("very essential", "essential"),
        ("very necessary", "necessary"),
        ("whole entire", "entire"),
        ("written down", "written"),
    ]

    func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        let lower = text.lowercased()
        let nsText = text as NSString
        var issues: [WritingIssue] = []

        for (phrase, replacement) in Self.redundantPhrases {
            var searchStart = lower.startIndex
            while let range = lower.range(of: phrase, range: searchStart..<lower.endIndex) {
                let nsRange = NSRange(range, in: text)
                guard nsRange.location + nsRange.length <= nsText.length else { break }

                let word = nsText.substring(with: nsRange)
                issues.append(WritingIssue(
                    type: .redundancy,
                    range: nsRange,
                    word: word,
                    message: "Redundant phrase — consider \"\(replacement)\"",
                    suggestions: [replacement]
                ))

                searchStart = range.upperBound
            }
        }

        return issues
    }
}
