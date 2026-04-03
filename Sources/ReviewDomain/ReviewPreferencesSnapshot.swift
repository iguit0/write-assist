// WriteAssist — macOS menu bar writing assistant
// Copyright © 2024 Igor Alves. All rights reserved.

import Foundation

/// An immutable snapshot of the user's writing preferences at the time an
/// analysis was requested. `FormalityLevel` and `AudienceLevel` are declared
/// in `PreferencesManager.swift` and reused here.
struct ReviewPreferencesSnapshot: Sendable, Equatable {
    let formality: FormalityLevel
    let audience: AudienceLevel
    let disabledRules: Set<String>
}
