// WriteAssist — macOS menu bar writing assistant
// Copyright © 2024 Igor Alves. All rights reserved.

import Foundation

public enum SelectionImportError: Error, Sendable {
    case accessibilityDenied
    case secureContext
    case noFocusedElement
    case noSelection
    case unsupportedElement
}
