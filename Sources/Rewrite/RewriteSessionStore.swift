// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import OSLog

/// The state of an explicit rewrite request.
public enum RewriteSessionState: Sendable {
    case idle
    /// A rewrite is in-flight for a document at the given revision.
    case rewriting(documentRevision: Int)
    /// One or more candidates are ready; the target range is stored for the accept flow.
    case ready(candidates: [RewriteCandidate], target: RewriteTarget, documentRevision: Int)
    /// The rewrite failed with a user-facing message.
    case failed(String, documentRevision: Int)
}

@MainActor
@Observable
public final class RewriteSessionStore {

    // MARK: - State

    public var rewriteState: RewriteSessionState = .idle
    /// Reserved for future multi-candidate selection UI. Currently set to the first
    /// candidate's ID on success; `RewriteCompareView` reads `candidates.first` directly
    /// until a picker is added.
    public var selectedCandidateID: UUID?
    /// The mode selected in the toolbar (persists across rewrites).
    public var selectedMode: RewriteMode = .grammarFix

    // MARK: - Computed shims

    public var isRewriting: Bool {
        if case .rewriting = rewriteState { return true }
        return false
    }

    public var candidates: [RewriteCandidate] {
        if case .ready(let c, _, _) = rewriteState { return c }
        return []
    }

    // MARK: - Internal

    private let engine: any RewriteEngine
    private var rewriteTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.writeassist", category: "RewriteSessionStore")

    // MARK: - Init

    public init() {
        self.engine = LocalFirstRewriteEngine()
    }

    /// Dependency-injection initialiser for testing and previews.
    init(engine: any RewriteEngine) {
        self.engine = engine
    }

    // MARK: - Request

    /// Resolves the best target from the current review-store selection and starts a rewrite.
    public func requestRewrite(mode: RewriteMode, from reviewStore: ReviewSessionStore) {
        guard let target = RewriteTargetResolver.resolve(from: reviewStore) else {
            logger.debug("requestRewrite: no target resolved — nothing selected")
            return
        }
        let sourceText = extractSourceText(target: target, from: reviewStore.document)
        guard !sourceText.isEmpty else {
            logger.debug("requestRewrite: source text is empty")
            return
        }

        let documentRevision = reviewStore.document.revision
        let documentID = reviewStore.document.id
        let policy = RewriteProviderPolicy(
            primary: CloudAIService.shared.provider,
            fallback: nil
        )
        let request = RewriteRequest(
            id: UUID(),
            documentID: documentID,
            documentRevision: documentRevision,
            target: target,
            sourceText: sourceText,
            mode: mode,
            providerPolicy: policy
        )

        rewriteTask?.cancel()
        rewriteState = .rewriting(documentRevision: documentRevision)
        selectedCandidateID = nil

        logger.info("Rewrite requested — mode: \(mode.rawValue), revision: \(documentRevision)")

        rewriteTask = Task {
            do {
                let result = try await self.engine.rewrite(request)
                guard !Task.isCancelled,
                      reviewStore.document.revision == documentRevision else {
                    self.logger.debug("Rewrite discarded — stale revision or cancelled")
                    if case .rewriting = self.rewriteState { self.rewriteState = .idle }
                    return
                }
                self.rewriteState = .ready(
                    candidates: result.candidates,
                    target: target,
                    documentRevision: documentRevision
                )
                self.selectedCandidateID = result.candidates.first?.id
                self.logger.info("Rewrite ready — \(result.candidates.count) candidate(s)")
            } catch {
                guard !Task.isCancelled else {
                    if case .rewriting = self.rewriteState { self.rewriteState = .idle }
                    return
                }
                self.rewriteState = .failed(error.localizedDescription, documentRevision: documentRevision)
                self.logger.error("Rewrite failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Accept / Reject

    /// Applies the chosen candidate through the review store's single mutation path.
    public func acceptCandidate(id: UUID, applying reviewStore: ReviewSessionStore) {
        guard case .ready(let candidates, let target, let rev) = rewriteState,
              rev == reviewStore.document.revision,
              let candidate = candidates.first(where: { $0.id == id }) else {
            logger.warning("acceptCandidate: state mismatch or candidate not found — ignoring")
            return
        }
        reviewStore.applyReplacement(
            range: target.nsRange,
            replacement: candidate.text,
            trigger: .rewriteApplied
        )
        rewriteState = .idle
        selectedCandidateID = nil
        logger.info("Accepted rewrite candidate \(id)")
    }

    /// Discards any pending or ready candidates without mutating the document.
    public func rejectCandidates() {
        rewriteTask?.cancel()
        rewriteTask = nil
        rewriteState = .idle
        selectedCandidateID = nil
        logger.info("Rewrite candidates rejected")
    }

    /// Alias kept for legacy call sites.
    public func clear() {
        rejectCandidates()
    }

    // MARK: - Helpers

    private func extractSourceText(target: RewriteTarget, from document: ReviewDocument) -> String {
        let nsText = document.text as NSString
        let range = target.nsRange
        guard range.location != NSNotFound,
              range.location + range.length <= nsText.length else {
            return ""
        }
        return nsText.substring(with: range)
    }
}
