// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

struct FormalityRule: WritingRule {
    let ruleID = "formality"
    let issueType = IssueType.style

    // Formal words to flag in informal mode
    private static let formalToInformal: [(formal: String, informal: String)] = [
        ("commence", "start"), ("terminate", "end"), ("utilize", "use"),
        ("facilitate", "help"), ("endeavor", "try"), ("ascertain", "find out"),
        ("subsequently", "then"), ("prior to", "before"), ("procure", "get"),
        ("remuneration", "pay"), ("peruse", "read"), ("ameliorate", "improve"),
        ("elucidate", "explain"), ("disseminate", "spread"), ("enumerate", "list"),
        ("expedite", "speed up"), ("in accordance with", "following"),
        ("at your earliest convenience", "soon"), ("pursuant to", "following"),
    ]

    // Informal words to flag in formal mode
    private static let informalToFormal: [(informal: String, formal: String)] = [
        ("gonna", "going to"), ("wanna", "want to"), ("gotta", "have to"),
        ("kinda", "kind of"), ("sorta", "sort of"), ("lemme", "let me"),
        ("gimme", "give me"), ("dunno", "do not know"), ("ain't", "is not"),
        ("y'all", "you all"), ("cuz", "because"), ("tho", "though"),
        ("thru", "through"), ("nite", "night"), ("awesome", "excellent"),
        ("stuff", "materials"), ("a lot", "significantly"), ("lots of", "numerous"),
        ("tons of", "a great deal of"), ("kids", "children"),
        ("pretty much", "largely"), ("right away", "immediately"),
        ("figure out", "determine"), ("nope", "no"), ("yep", "yes"),
        ("yeah", "yes"), ("lol", ""), ("btw", "by the way"),
        ("fyi", "for your information"), ("asap", "as soon as possible"),
    ]

    // Contractions to flag in formal mode
    private static let contractions: [(contraction: String, expansion: String)] = [
        ("can't", "cannot"), ("won't", "will not"), ("don't", "do not"),
        ("doesn't", "does not"), ("didn't", "did not"), ("isn't", "is not"),
        ("aren't", "are not"), ("wasn't", "was not"), ("weren't", "were not"),
        ("hasn't", "has not"), ("haven't", "have not"), ("hadn't", "had not"),
        ("shouldn't", "should not"), ("wouldn't", "would not"),
        ("couldn't", "could not"), ("I'm", "I am"), ("I've", "I have"),
        ("I'll", "I will"), ("we're", "we are"), ("they're", "they are"),
        ("you're", "you are"), ("it's", "it is"),
    ]

    func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        // Formality level is read from the snapshot stored in NLAnalysis context.
        // This avoids accessing @MainActor PreferencesManager from a nonisolated context.
        let formality = analysis.formalityLevel
        guard formality != .neutral else { return [] }

        let lower = text.lowercased()
        let nsText = text as NSString
        var issues: [WritingIssue] = []

        if formality == .informal {
            // Flag overly formal language
            for (formal, informal) in Self.formalToInformal {
                findAndReport(
                    phrase: formal, in: lower, nsText: nsText, fullText: text,
                    message: "Too formal for informal writing — try \"\(informal)\"",
                    suggestion: informal, issues: &issues
                )
            }
        } else if formality == .formal {
            // Flag informal language
            for (informal, formal) in Self.informalToFormal {
                findAndReport(
                    phrase: informal, in: lower, nsText: nsText, fullText: text,
                    message: formal.isEmpty
                        ? "Informal language — consider removing"
                        : "Informal language — try \"\(formal)\"",
                    suggestion: formal, issues: &issues
                )
            }
            // Flag contractions
            for (contraction, expansion) in Self.contractions {
                findAndReport(
                    phrase: contraction, in: lower, nsText: nsText, fullText: text,
                    message: "Avoid contractions in formal writing — use \"\(expansion)\"",
                    suggestion: expansion, issues: &issues
                )
            }
        }

        return issues
    }

    private func findAndReport(
        phrase: String,
        in lower: String,
        nsText: NSString,
        fullText: String,
        message: String,
        suggestion: String,
        issues: inout [WritingIssue]
    ) {
        var searchStart = lower.startIndex
        while let range = lower.range(of: phrase, range: searchStart..<lower.endIndex) {
            let nsRange = NSRange(range, in: fullText)
            guard nsRange.location + nsRange.length <= nsText.length else { break }

            let word = nsText.substring(with: nsRange)
            issues.append(WritingIssue(
                type: .style,
                range: nsRange,
                word: word,
                message: message,
                suggestions: suggestion.isEmpty ? [] : [suggestion]
            ))

            searchStart = range.upperBound
        }
    }
}
