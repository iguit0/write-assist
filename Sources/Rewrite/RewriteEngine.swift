// WriteAssist — macOS menu bar writing assistant
// Copyright © 2024 Igor Alves. All rights reserved.

import Foundation

protocol RewriteEngine: Sendable {
    func rewrite(_ request: RewriteRequest) async throws -> RewriteResult
}
