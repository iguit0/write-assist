// WriteAssist — macOS menu bar writing assistant
// Copyright © 2024 Igor Alves. All rights reserved.

import Foundation

public enum RewriteMode: String, Sendable, CaseIterable {
    case grammarFix
    case natural
    case shorter
    case formal
}
