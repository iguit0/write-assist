// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import Testing
@testable import WriteAssistCore

private struct StubRewriteEngine: RewriteEngine {
    func rewrite(_ request: RewriteRequest) async throws -> RewriteResult {
        RewriteResult(
            requestID: request.id,
            candidates: [
                RewriteCandidate(
                    id: UUID(),
                    provider: .ollama,
                    modelName: "stub",
                    text: "rewritten: \(request.sourceText)"
                )
            ]
        )
    }
}

private struct StubReviewEngine: ReviewEngine {
    func analyze(
        document: ReviewDocument,
        preferences: ReviewPreferencesSnapshot
    ) async -> ReviewAnalysisSnapshot {
        await PlaceholderReviewEngine().analyze(document: document, preferences: preferences)
    }
}

@Suite("ReviewSelectionPanelStore")
struct ReviewSelectionPanelStoreTests {

    @Test("requestRewrite sets activeRewriteMode and triggers rewrite")
    @MainActor
    func requestRewriteSetsMode() {
        let reviewStore = ReviewSessionStore(engine: StubReviewEngine())
        let rewriteStore = RewriteSessionStore(engine: StubRewriteEngine())
        let store = ReviewSelectionPanelStore(reviewStore: reviewStore, rewriteStore: rewriteStore)

        reviewStore.replaceText("Hello world", autoReview: false)
        store.showImportedSelection(ImportedSelection(
            text: "Hello world",
            metadata: ImportedSelectionMetadata(appName: "TextEdit", bundleIdentifier: nil, importedAt: Date())
        ))

        store.requestRewrite(mode: .natural)

        #expect(store.activeRewriteMode == .natural)
        #expect(rewriteStore.isRewriting)
    }

    @Test("requestRewrite sets selectedEditorRange to full text")
    @MainActor
    func requestRewriteSetsFullRange() {
        let reviewStore = ReviewSessionStore(engine: StubReviewEngine())
        let rewriteStore = RewriteSessionStore(engine: StubRewriteEngine())
        let store = ReviewSelectionPanelStore(reviewStore: reviewStore, rewriteStore: rewriteStore)

        let text = "Hello world"
        reviewStore.replaceText(text, autoReview: false)
        store.showImportedSelection(ImportedSelection(
            text: text,
            metadata: ImportedSelectionMetadata(appName: nil, bundleIdentifier: nil, importedAt: Date())
        ))

        store.requestRewrite(mode: .grammarFix)

        #expect(reviewStore.selectedEditorRange == NSRange(location: 0, length: (text as NSString).length))
    }

    @Test("rejectRewrite clears activeRewriteMode and rewrite state")
    @MainActor
    func rejectRewriteClears() {
        let reviewStore = ReviewSessionStore(engine: StubReviewEngine())
        let rewriteStore = RewriteSessionStore(engine: StubRewriteEngine())
        let store = ReviewSelectionPanelStore(reviewStore: reviewStore, rewriteStore: rewriteStore)

        store.activeRewriteMode = .formal
        store.rejectRewrite()

        #expect(store.activeRewriteMode == nil)
    }

    @Test("reset clears rewrite state alongside existing state")
    @MainActor
    func resetClearsRewriteState() {
        let reviewStore = ReviewSessionStore(engine: StubReviewEngine())
        let rewriteStore = RewriteSessionStore(engine: StubRewriteEngine())
        let store = ReviewSelectionPanelStore(reviewStore: reviewStore, rewriteStore: rewriteStore)

        store.showImportedSelection(ImportedSelection(
            text: "test",
            metadata: ImportedSelectionMetadata(appName: nil, bundleIdentifier: nil, importedAt: Date())
        ))
        store.activeRewriteMode = .shorter

        store.reset()

        #expect(store.phase == .idle)
        #expect(store.importedSelection == nil)
        #expect(store.activeRewriteMode == nil)
    }

    @Test("requestRewrite does nothing when document text is empty")
    @MainActor
    func requestRewriteIgnoresEmptyText() {
        let reviewStore = ReviewSessionStore(engine: StubReviewEngine())
        let rewriteStore = RewriteSessionStore(engine: StubRewriteEngine())
        let store = ReviewSelectionPanelStore(reviewStore: reviewStore, rewriteStore: rewriteStore)

        store.requestRewrite(mode: .grammarFix)

        #expect(store.activeRewriteMode == nil)
        #expect(!rewriteStore.isRewriting)
    }
}
