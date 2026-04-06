// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

public enum RewriteMode: String, Sendable, CaseIterable {
    case grammarFix
    case natural
    case shorter
    case formal

    var label: String {
        switch self {
        case .grammarFix: return "Fix Grammar"
        case .natural:    return "Natural"
        case .shorter:    return "Shorter"
        case .formal:     return "Formal"
        }
    }

    /// Maps to the legacy `AIRewriteStyle` used by `CloudAIService`.
    var aiStyle: AIRewriteStyle {
        switch self {
        case .grammarFix: return .grammarFix
        case .natural:    return .rephrase
        case .shorter:    return .concise
        case .formal:     return .formal
        }
    }
}
