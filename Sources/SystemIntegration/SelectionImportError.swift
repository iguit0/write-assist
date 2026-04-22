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

extension SelectionImportError {
    public var userFacingMessage: String {
        switch self {
        case .accessibilityDenied:
            return "WriteAssist needs Accessibility permission to read selected text from other apps."
        case .secureContext:
            return "The focused field is secure (e.g. a password field) and cannot be imported."
        case .noFocusedElement:
            return "No text field is focused. Click inside a text field in another app, then try Review Selection."
        case .noSelection:
            return "No text is selected. Select some text in another app, then try Review Selection."
        case .unsupportedElement:
            return "The focused element does not support text selection."
        }
    }
}
