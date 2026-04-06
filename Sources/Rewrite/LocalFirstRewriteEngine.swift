// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.writeassist", category: "LocalFirstRewriteEngine")

/// Rewrite engine that always tries Ollama (local) first, then falls back to the
/// configured cloud provider. No ambient monitors are started or observed.
///
/// `CloudAIService` is `@MainActor`. Synchronous properties are captured via
/// `MainActor.run`; async methods auto-hop to the main actor when awaited.
struct LocalFirstRewriteEngine: RewriteEngine {

    func rewrite(_ request: RewriteRequest) async throws -> RewriteResult {
        let style = request.mode.aiStyle

        // Capture synchronous main-actor properties in one hop.
        let (service, ollamaModel, configuredProvider) = await MainActor.run {
            (CloudAIService.shared, CloudAIService.shared.ollamaModelName, CloudAIService.shared.provider)
        }

        // --- Local-first: try Ollama if a model is configured and the server is up ---
        if !ollamaModel.isEmpty {
            let reachable = await service.isOllamaReachable()
            if reachable {
                do {
                    let (text, model) = try await service.rewriteWithProvider(
                        .ollama, text: request.sourceText, style: style
                    )
                    logger.info("Rewrite via Ollama (\(model)) succeeded")
                    let candidate = RewriteCandidate(id: UUID(), provider: .ollama, modelName: model, text: text)
                    return RewriteResult(requestID: request.id, candidates: [candidate])
                } catch {
                    logger.warning("Ollama rewrite failed (\(error.localizedDescription)), trying cloud fallback")
                }
            } else {
                logger.debug("Ollama not reachable — skipping local provider")
            }
        }

        // --- Cloud fallback ---
        let cloudProvider: AIProvider
        if request.providerPolicy.primary != .ollama {
            cloudProvider = request.providerPolicy.primary
        } else if let fallback = request.providerPolicy.fallback, fallback != .ollama {
            cloudProvider = fallback
        } else {
            // Policy has no usable cloud provider; use whatever cloud service is configured.
            // Last resort: default to .anthropic if the configured provider is also .ollama
            // (e.g. user has Ollama set globally but no explicit cloud fallback). This will
            // surface a CloudAIError.noAPIKey if no Anthropic key is configured — not silent.
            cloudProvider = configuredProvider != .ollama ? configuredProvider : .anthropic
        }

        let (text, model) = try await service.rewriteWithProvider(
            cloudProvider, text: request.sourceText, style: style
        )
        logger.info("Rewrite via \(cloudProvider.rawValue) (\(model)) succeeded")
        let candidate = RewriteCandidate(id: UUID(), provider: cloudProvider, modelName: model, text: text)
        return RewriteResult(requestID: request.id, candidates: [candidate])
    }
}
