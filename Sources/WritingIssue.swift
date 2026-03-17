// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import SwiftUI

enum IssueType: Sendable {
    case spelling
    case grammar
    case doubleWord
    case capitalization
    case hedging
    case redundancy
    case runOn
    case passiveVoice
    case wordiness
    case confusedWord
    case fragment
    case inclusiveLanguage
    case style
    case ai

    var color: Color {
        switch self {
        case .spelling:             return .red
        case .grammar:              return .orange
        case .doubleWord:           return .red
        case .capitalization:       return .orange
        case .hedging:              return .purple
        case .redundancy:           return .purple
        case .runOn:                return .blue
        case .passiveVoice:         return .blue
        case .wordiness:            return .purple
        case .confusedWord:         return .orange
        case .fragment:             return .blue
        case .inclusiveLanguage:    return .green
        case .style:                return .green
        case .ai:                   return .indigo
        }
    }

    var icon: String {
        switch self {
        case .spelling:             return "textformat.abc"
        case .grammar:              return "textformat"
        case .doubleWord:           return "doc.on.doc"
        case .capitalization:       return "textformat.size"
        case .hedging:              return "questionmark.circle"
        case .redundancy:           return "minus.circle"
        case .runOn:                return "arrow.right.to.line"
        case .passiveVoice:         return "arrow.uturn.left"
        case .wordiness:            return "text.word.spacing"
        case .confusedWord:         return "arrow.triangle.swap"
        case .fragment:             return "text.badge.xmark"
        case .inclusiveLanguage:    return "person.2"
        case .style:                return "paintbrush"
        case .ai:                   return "sparkles"
        }
    }

    var categoryLabel: String {
        switch self {
        case .spelling:             return "Spelling"
        case .grammar:              return "Grammar"
        case .doubleWord:           return "Double Word"
        case .capitalization:       return "Capitalization"
        case .hedging:              return "Hedging"
        case .redundancy:           return "Redundancy"
        case .runOn:                return "Run-on"
        case .passiveVoice:         return "Passive Voice"
        case .wordiness:            return "Wordiness"
        case .confusedWord:         return "Confused Word"
        case .fragment:             return "Fragment"
        case .inclusiveLanguage:    return "Inclusive Language"
        case .style:                return "Style"
        case .ai:                   return "AI Suggestion"
        }
    }

    var category: IssueCategory {
        switch self {
        case .spelling, .grammar, .doubleWord, .capitalization, .confusedWord:
            return .correctness
        case .passiveVoice, .wordiness, .runOn, .fragment:
            return .clarity
        case .hedging, .redundancy:
            return .engagement
        case .inclusiveLanguage, .style, .ai:
            return .delivery
        }
    }
}

enum IssueCategory: String, CaseIterable, Sendable {
    case correctness = "Correctness"
    case clarity = "Clarity"
    case engagement = "Engagement"
    case delivery = "Delivery"

    var color: Color {
        switch self {
        case .correctness:  return .red
        case .clarity:      return .blue
        case .engagement:   return .purple
        case .delivery:     return .green
        }
    }
}

struct WritingIssue: Identifiable, Sendable {
    let type: IssueType
    let ruleID: String
    let range: NSRange
    let word: String
    let message: String
    let suggestions: [String]

    /// Stable identity so SwiftUI diffing/caches don't churn on every re-check.
    var id: String {
        "\(ruleID):\(range.location):\(range.length):\(word.lowercased())"
    }
}
