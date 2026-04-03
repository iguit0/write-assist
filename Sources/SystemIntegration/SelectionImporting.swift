// WriteAssist — macOS menu bar writing assistant
// Copyright © 2024 Igor Alves. All rights reserved.

import Foundation

// ImportedSelectionMetadata is defined in Sources/ReviewDomain/ReviewDocument.swift.
// Do NOT redefine it here — reference it directly.

public struct ImportedSelection: Sendable {
    public let text: String
    public let metadata: ImportedSelectionMetadata

    public init(text: String, metadata: ImportedSelectionMetadata) {
        self.text = text
        self.metadata = metadata
    }
}

public protocol SelectionImporting: Sendable {
    func importCurrentSelection() async throws -> ImportedSelection
}
