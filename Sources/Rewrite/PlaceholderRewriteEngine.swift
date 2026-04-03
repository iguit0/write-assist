// WriteAssist — macOS menu bar writing assistant
// Copyright © 2024 Igor Alves. All rights reserved.

struct PlaceholderRewriteEngine: RewriteEngine {
    func rewrite(_ request: RewriteRequest) async throws -> RewriteResult {
        RewriteResult(requestID: request.id, candidates: [])
    }
}
