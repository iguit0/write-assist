// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import Testing
@testable import WriteAssistCore

private struct StubReviewEngine: ReviewEngine {
    func analyze(
        document: ReviewDocument,
        preferences: ReviewPreferencesSnapshot
    ) async -> ReviewAnalysisSnapshot {
        await PlaceholderReviewEngine().analyze(document: document, preferences: preferences)
    }
}

@Suite("ReviewSessionStore")
struct ReviewSessionStoreTests {
    @Test("replaceText clears selection state")
    @MainActor
    func replaceTextClearsSelectionState() {
        let store = ReviewSessionStore(engine: StubReviewEngine())
        store.selectedIssueID = "issue-id"
        store.selectedParagraphID = "paragraph-id"
        store.selectedSentenceID = "sentence-id"
        store.selectedEditorRange = NSRange(location: 3, length: 4)

        store.replaceText("Updated text", autoReview: false)

        #expect(store.selectedIssueID == nil)
        #expect(store.selectedParagraphID == nil)
        #expect(store.selectedSentenceID == nil)
        #expect(store.selectedEditorRange == nil)
    }
}
