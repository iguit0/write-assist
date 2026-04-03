// WriteAssist — macOS menu bar writing assistant
// Copyright © 2024 Igor Alves. All rights reserved.

import Foundation

// NSRange is used as an associated value below. It is a @frozen struct bridged from
// Objective-C. In the existing codebase (ReviewAnalysisSnapshot.swift) NSRange is
// used as a stored property of Sendable+Equatable structs without any explicit
// conformance extension — the same approach is used here.

public enum RewriteTarget: Sendable, Equatable {
    case sentence(id: String, range: NSRange)
    case paragraph(id: String, range: NSRange)
    case customSelection(range: NSRange)
}

public struct RewriteRequest: Identifiable, Sendable {
    public let id: UUID
    public let documentID: UUID
    public let documentRevision: Int
    public let target: RewriteTarget
    public let sourceText: String
    public let mode: RewriteMode
    // providerPolicy is internal — RewriteProviderPolicy references AIProvider which is internal
    let providerPolicy: RewriteProviderPolicy

    init(id: UUID, documentID: UUID, documentRevision: Int, target: RewriteTarget, sourceText: String, mode: RewriteMode, providerPolicy: RewriteProviderPolicy) {
        self.id = id
        self.documentID = documentID
        self.documentRevision = documentRevision
        self.target = target
        self.sourceText = sourceText
        self.mode = mode
        self.providerPolicy = providerPolicy
    }
}
