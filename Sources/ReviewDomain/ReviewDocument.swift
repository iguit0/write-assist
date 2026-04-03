// WriteAssist — macOS menu bar writing assistant
// Copyright © 2024 Igor Alves. All rights reserved.

import Foundation

/// A document held in the Review Workbench, identified by a stable UUID and
/// versioned by a monotonically increasing revision counter.
public struct ReviewDocument: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var text: String
    public var source: ReviewDocumentSource
    public var revision: Int
    public var updatedAt: Date

    public init(id: UUID, text: String, source: ReviewDocumentSource, revision: Int, updatedAt: Date) {
        self.id = id
        self.text = text
        self.source = source
        self.revision = revision
        self.updatedAt = updatedAt
    }
}

/// How the document arrived in the workbench.
public enum ReviewDocumentSource: Sendable, Equatable {
    case manual
    case paste
    case importedSelection(ImportedSelectionMetadata)
}

/// Provenance metadata for a document imported from another application.
public struct ImportedSelectionMetadata: Sendable, Equatable {
    public let appName: String?
    public let bundleIdentifier: String?
    public let importedAt: Date

    public init(appName: String?, bundleIdentifier: String?, importedAt: Date) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.importedAt = importedAt
    }
}
