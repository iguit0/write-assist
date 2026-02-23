// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import NaturalLanguage

struct PassiveVoiceRule: WritingRule {
    let ruleID = "passiveVoice"
    let issueType = IssueType.passiveVoice

    // Single-word "to be" forms — direct passive auxiliaries
    private static let toBeVerbs: Set<String> = [
        "is", "are", "was", "were", "be", "been", "being", "am",
    ]

    // Modal/auxiliary verbs that precede "be/been/being" in passive chains
    private static let auxiliaryVerbs: Set<String> = [
        "has", "have", "had", "will", "shall",
        "could", "would", "might", "must", "should", "can", "may",
    ]

    // Irregular past participles not caught by the -ed suffix check.
    // Sourced from standard English irregular verb tables.
    // swiftlint:disable:next identifier_name
    private static let irregularPastParticiples: Set<String> = [
        // -ught/-ought
        "taught", "caught", "bought", "brought", "fought", "thought",
        // -elt/-elt
        "felt", "dealt", "dwelt",
        // -ept
        "kept", "slept", "swept", "wept", "crept",
        // -eft
        "left", "bereft",
        // -ent
        "sent", "spent", "lent", "bent", "meant", "went",
        // -ilt
        "built", "spilt",
        // -old/-eld
        "told", "sold", "held",
        // -ood
        "stood", "understood", "withstood",
        // -ound
        "found", "ground", "bound", "wound",
        // -aid
        "paid", "said", "laid",
        // -ade
        "made",
        // irregular -ed (same form as base or different pronunciation)
        "bred", "fed", "led", "bled", "fled", "shed", "sped", "wed", "read",
        // -ung
        "rung", "sung", "clung", "stung", "swung", "wrung", "hung", "flung", "slung", "sprung",
        // -unk
        "drunk", "sunk", "stunk", "shrunk",
        // -un
        "run", "spun", "won", "begun",
        // -um
        "swum",
        // -at/-ot/-ut/-it/-et
        "sat", "shot", "got", "cut", "put", "shut", "hit", "lit", "knit", "spit", "split",
        "quit", "set", "met", "bet",
        // -urt/-ost/-uck/-ug/-id/-ad
        "hurt", "lost", "cost", "stuck", "struck", "dug", "slid", "hid", "rid", "bid",
        "had", "spread",
        // unique/other
        "come", "become", "let", "burst", "cast", "forecast",
        // -en forms (already caught by suffix but included for completeness)
        "written", "taken", "spoken", "broken", "chosen", "driven", "risen", "ridden",
        "hidden", "bitten", "eaten", "fallen", "forgotten", "forgiven", "given", "frozen",
        "shaken", "stolen", "woken", "awoken", "arisen", "beaten", "forbidden",
        // -wn forms (already caught by suffix but included for completeness)
        "drawn", "blown", "flown", "grown", "known", "shown", "sown", "sewn",
        "mown", "thrown", "sworn", "worn", "torn", "withdrawn",
        // -ne forms
        "done", "gone", "borne",
    ]

    private static func isPastParticiple(_ word: String) -> Bool {
        word.hasSuffix("ed") || irregularPastParticiples.contains(word)
    }

    func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        var issues: [WritingIssue] = []
        let tags = analysis.wordPOSTags

        // Look for pattern: "to be" verb followed by past participle (VBN)
        for i in 0..<tags.count {
            let (word, _, _) = tags[i]
            let lower = word.lowercased()

            guard Self.toBeVerbs.contains(lower) else { continue }

            // Check the next word (skip one if adverb is in between)
            var nextIdx = i + 1
            if nextIdx < tags.count, tags[nextIdx].tag == .adverb {
                nextIdx += 1
            }
            guard nextIdx < tags.count else { continue }

            let (nextWord, nextTag, _) = tags[nextIdx]
            // NLTagger tags past participles as .verb — check common -ed/-en endings
            guard nextTag == .verb else { continue }
            let nextLower = nextWord.lowercased()
            guard nextLower.hasSuffix("ed") || nextLower.hasSuffix("en")
                || nextLower.hasSuffix("wn") || nextLower.hasSuffix("ne") else { continue }

            // Build the passive phrase range
            let startRange = tags[i].range
            let endRange = tags[nextIdx].range
            let phraseRange = startRange.lowerBound..<endRange.upperBound
            let nsRange = NSRange(phraseRange, in: text)
            let phrase = String(text[phraseRange])

            issues.append(WritingIssue(
                type: .passiveVoice,
                range: nsRange,
                word: phrase,
                message: "Passive voice — consider using active voice",
                suggestions: []
            ))
        }

        return issues
    }
}
