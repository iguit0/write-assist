// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

enum FormalityLevel: String, CaseIterable, Sendable, Codable {
    case informal = "Informal"
    case neutral = "Neutral"
    case formal = "Formal"
}

enum AudienceLevel: String, CaseIterable, Sendable, Codable {
    case general = "General"
    case knowledgeable = "Knowledgeable"
    case expert = "Expert"

    var targetGradeLevel: Double {
        switch self {
        case .general:       return 8
        case .knowledgeable: return 12
        case .expert:        return 16
        }
    }
}

enum WritingPreset: String, CaseIterable, Sendable, Codable {
    case academic = "Academic"
    case business = "Business"
    case email = "Email"
    case creative = "Creative"
    case casual = "Casual"

    var defaultFormality: FormalityLevel {
        switch self {
        case .academic:  return .formal
        case .business:  return .formal
        case .email:     return .neutral
        case .creative:  return .neutral
        case .casual:    return .informal
        }
    }

    var defaultAudience: AudienceLevel {
        switch self {
        case .academic:  return .expert
        case .business:  return .knowledgeable
        case .email:     return .general
        case .creative:  return .general
        case .casual:    return .general
        }
    }
}

@MainActor
@Observable
final class PreferencesManager: @unchecked Sendable {
    static let shared = PreferencesManager()

    var formalityLevel: FormalityLevel {
        didSet { UserDefaults.standard.set(formalityLevel.rawValue, forKey: "formalityLevel") }
    }
    var audienceLevel: AudienceLevel {
        didSet { UserDefaults.standard.set(audienceLevel.rawValue, forKey: "audienceLevel") }
    }
    var writingPreset: WritingPreset {
        didSet {
            UserDefaults.standard.set(writingPreset.rawValue, forKey: "writingPreset")
            // Apply preset defaults
            formalityLevel = writingPreset.defaultFormality
            audienceLevel = writingPreset.defaultAudience
        }
    }

    // Rule toggles — keyed by ruleID
    var disabledRules: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(disabledRules), forKey: "disabledRules")
        }
    }

    func isRuleEnabled(_ ruleID: String) -> Bool {
        !disabledRules.contains(ruleID)
    }

    func toggleRule(_ ruleID: String) {
        if disabledRules.contains(ruleID) {
            disabledRules.remove(ruleID)
        } else {
            disabledRules.insert(ruleID)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        self.formalityLevel = FormalityLevel(rawValue: defaults.string(forKey: "formalityLevel") ?? "") ?? .neutral
        self.audienceLevel = AudienceLevel(rawValue: defaults.string(forKey: "audienceLevel") ?? "") ?? .general
        self.writingPreset = WritingPreset(rawValue: defaults.string(forKey: "writingPreset") ?? "") ?? .email
        self.disabledRules = Set(defaults.stringArray(forKey: "disabledRules") ?? [])
    }
}
