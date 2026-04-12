// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

@MainActor
@Observable
public final class ReviewSelectionPanelStore {
    public enum Phase: Equatable {
        case idle
        case importing
        case error(SelectionImportError)
        case review
    }

    public let reviewStore: ReviewSessionStore
    public let rewriteStore: RewriteSessionStore
    public private(set) var phase: Phase = .idle
    public private(set) var importedSelection: ImportedSelection?
    public var activeRewriteMode: RewriteMode?

    public init(reviewStore: ReviewSessionStore, rewriteStore: RewriteSessionStore) {
        self.reviewStore = reviewStore
        self.rewriteStore = rewriteStore
    }

    // MARK: - Import lifecycle

    public func beginImport() {
        importedSelection = nil
        activeRewriteMode = nil
        rewriteStore.rejectCandidates()
        clearReviewSession()
        phase = .importing
    }

    public func showImportedSelection(_ selection: ImportedSelection) {
        importedSelection = selection
        phase = .review
    }

    public func showImportError(_ error: SelectionImportError) {
        importedSelection = nil
        activeRewriteMode = nil
        rewriteStore.rejectCandidates()
        clearReviewSession()
        phase = .error(error)
    }

    public func reset() {
        importedSelection = nil
        activeRewriteMode = nil
        rewriteStore.rejectCandidates()
        clearReviewSession()
        phase = .idle
    }

    // MARK: - Rewrite lifecycle

    public func requestRewrite(mode: RewriteMode) {
        let text = reviewStore.document.text
        guard !text.isEmpty else { return }
        activeRewriteMode = mode
        reviewStore.selectedEditorRange = NSRange(location: 0, length: (text as NSString).length)
        rewriteStore.requestRewrite(mode: mode, from: reviewStore)
    }

    public func rejectRewrite() {
        activeRewriteMode = nil
        rewriteStore.rejectCandidates()
    }

    // MARK: - Private

    private func clearReviewSession() {
        reviewStore.cancelReview()
        reviewStore.replaceText("", autoReview: false)
    }
}
