// WriteAssist — macOS menu bar writing assistant
// Copyright © 2024 Igor Alves. All rights reserved.

public enum AppMode: String, Sendable, CaseIterable {
    case legacyInline
    case reviewWorkbenchHybrid
    case reviewWorkbenchOnly
}
