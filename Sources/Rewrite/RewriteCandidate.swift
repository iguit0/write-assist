// WriteAssist — macOS menu bar writing assistant
// Copyright © 2024 Igor Alves. All rights reserved.

import Foundation

// AIProvider is defined in CloudAIService.swift as:
//   enum AIProvider: String, CaseIterable, Sendable, Codable { case anthropic, openai, ollama }
// Do NOT redeclare it here — reference it directly.

public struct RewriteCandidate: Identifiable, Sendable {
    public let id: UUID
    // provider is internal — AIProvider is declared internal in CloudAIService.swift
    let provider: AIProvider
    public let modelName: String
    public let text: String

    init(id: UUID, provider: AIProvider, modelName: String, text: String) {
        self.id = id
        self.provider = provider
        self.modelName = modelName
        self.text = text
    }
}

public struct RewriteResult: Sendable {
    public let requestID: UUID
    public let candidates: [RewriteCandidate]

    init(requestID: UUID, candidates: [RewriteCandidate]) {
        self.requestID = requestID
        self.candidates = candidates
    }
}
