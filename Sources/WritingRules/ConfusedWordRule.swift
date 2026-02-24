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

    private static let pairs: [ConfusedPair] = [
        ConfusedPair(words: ["affect", "effect"],
                     hint: "'Affect' is usually a verb; 'effect' is usually a noun."),
        ConfusedPair(words: ["then", "than"],
                     hint: "'Then' refers to time; 'than' is for comparisons."),
        ConfusedPair(words: ["loose", "lose"],
                     hint: "'Loose' means not tight; 'lose' means to misplace."),
        ConfusedPair(words: ["accept", "except"],
                     hint: "'Accept' means to receive; 'except' means to exclude."),
        ConfusedPair(words: ["compliment", "complement"],
                     hint: "'Compliment' is praise; 'complement' means to complete."),
        ConfusedPair(words: ["principal", "principle"],
                     hint: "'Principal' means main; 'principle' is a rule."),
        ConfusedPair(words: ["stationary", "stationery"],
                     hint: "'Stationary' means not moving; 'stationery' is paper."),
        ConfusedPair(words: ["advice", "advise"],
                     hint: "'Advice' is a noun; 'advise' is a verb."),
        ConfusedPair(words: ["breath", "breathe"],
                     hint: "'Breath' is a noun; 'breathe' is a verb."),
        ConfusedPair(words: ["peace", "piece"],
                     hint: "'Peace' is tranquility; 'piece' is a part."),
        ConfusedPair(words: ["weather", "whether"],
                     hint: "'Weather' is climate; 'whether' introduces alternatives."),
        ConfusedPair(words: ["desert", "dessert"],
                     hint: "'Desert' is dry area; 'dessert' is a sweet course."),
        ConfusedPair(words: ["farther", "further"],
                     hint: "'Farther' is physical distance; 'further' is figurative."),
        ConfusedPair(words: ["fewer", "less"],
                     hint: "'Fewer' for countable; 'less' for uncountable."),
        ConfusedPair(words: ["allude", "elude"],
                     hint: "'Allude' means to reference; 'elude' means to escape."),
        ConfusedPair(words: ["discreet", "discrete"],
                     hint: "'Discreet' means prudent; 'discrete' means separate."),
        ConfusedPair(words: ["elicit", "illicit"],
                     hint: "'Elicit' means to draw out; 'illicit' means illegal."),
        ConfusedPair(words: ["eminent", "imminent"],
                     hint: "'Eminent' means distinguished; 'imminent' means impending."),
        ConfusedPair(words: ["flaunt", "flout"],
                     hint: "'Flaunt' means to show off; 'flout' means to disregard."),
        ConfusedPair(words: ["imply", "infer"],
                     hint: "'Imply' means to suggest; 'infer' means to deduce."),
        ConfusedPair(words: ["precede", "proceed"],
                     hint: "'Precede' means come before; 'proceed' means continue."),
        ConfusedPair(words: ["bare", "bear"],
                     hint: "'Bare' means uncovered; 'bear' means to carry."),
        ConfusedPair(words: ["coarse", "course"],
                     hint: "'Coarse' means rough; 'course' is a path or class."),
        ConfusedPair(words: ["ensure", "insure"],
                     hint: "'Ensure' means make certain; 'insure' is about insurance."),
        ConfusedPair(words: ["hoard", "horde"],
                     hint: "'Hoard' is a stockpile; 'horde' is a large group."),
        ConfusedPair(words: ["lead", "led"],
                     hint: "'Lead' (present) vs 'led' (past tense)."),
        ConfusedPair(words: ["moral", "morale"],
                     hint: "'Moral' relates to right/wrong; 'morale' is spirit."),
        ConfusedPair(words: ["waist", "waste"],
                     hint: "'Waist' is a body part; 'waste' means to squander."),
        ConfusedPair(words: ["averse", "adverse"],
                     hint: "'Averse' means opposed; 'adverse' means harmful."),
        ConfusedPair(words: ["conscience", "conscious"],
                     hint: "'Conscience' is moral sense; 'conscious' means aware."),
        ConfusedPair(words: ["phase", "faze"],
                     hint: "'Phase' is a stage; 'faze' means to disturb."),
    ]

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

        for (word, tag, range) in analysis.wordPOSTags {
            let lower = word.lowercased()
            guard let matchingPairs = Self.wordToPairs[lower] else { continue }

            for pair in matchingPairs {
                // Use POS tag context to determine if word might be confused
                let shouldFlag = shouldFlagWord(lower, tag: tag, pair: pair)
                if shouldFlag {
                    let nsRange = NSRange(range, in: text)
                    let alternatives = pair.words.filter { $0.lowercased() != lower }
                    issues.append(WritingIssue(
                        type: .confusedWord,
                        range: nsRange,
                        word: word,
                        message: pair.hint,
                        suggestions: alternatives
                    ))
                }
            }
        }

        return issues
    }

    private func shouldFlagWord(_ word: String, tag: NLTag?, pair: ConfusedPair) -> Bool {
        // Use POS context to detect likely confusion
        // "affect" should be a verb, "effect" should be a noun
        switch word {
        case "affect":
            // If tagged as noun, might be confused with "effect"
            return tag == .noun
        case "effect":
            // If tagged as verb, might be confused with "affect"
            return tag == .verb
        case "advice":
            return tag == .verb
        case "advise":
            return tag == .noun
        case "breath":
            return tag == .verb
        case "breathe":
            return tag == .noun
        case "lead":
            // "lead" as past tense instead of "led"
            return false // Too ambiguous without more context
        case "less":
            // Would need to check if followed by countable noun — complex
            return false
        case "fewer":
            return false
        default:
            // For most pairs, we can't reliably detect confusion with POS alone.
            // Only flag when we have high confidence.
            return false
        }
    }
}
