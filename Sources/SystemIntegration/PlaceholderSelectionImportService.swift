// WriteAssist — macOS menu bar writing assistant
// Copyright © 2024 Igor Alves. All rights reserved.

public struct PlaceholderSelectionImportService: SelectionImporting {
    public init() {}

    public func importCurrentSelection() async throws -> ImportedSelection {
        throw SelectionImportError.noSelection
    }
}
