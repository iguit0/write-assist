// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

@MainActor
@Observable
public final class RewriteSessionStore {
    public var target: RewriteTarget?
    public var mode: RewriteMode?
    public var candidates: [RewriteCandidate] = []
    public var isRewriting = false
    // activeProvider is internal — AIProvider is declared internal in CloudAIService.swift
    var activeProvider: AIProvider?

    public init() {}

    public func clear() {
        target = nil
        mode = nil
        candidates = []
        isRewriting = false
        activeProvider = nil
    }
}
