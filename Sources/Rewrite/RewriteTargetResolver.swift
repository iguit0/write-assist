// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

/// Resolves the best `RewriteTarget` from the current `ReviewSessionStore` selection state.
///
/// Resolution order (first match wins):
/// 1. Selected sentence — requires a `.ready` analysis snapshot.
/// 2. Selected paragraph — requires a `.ready` analysis snapshot.
/// 3. Explicit editor selection range — available at any analysis state.
enum RewriteTargetResolver {

    /// Returns the best target for a rewrite, or `nil` if nothing is selected.
    @MainActor
    static func resolve(from store: ReviewSessionStore) -> RewriteTarget? {
        // Sentence and paragraph resolution require a ready snapshot.
        if case .ready(let snapshot) = store.analysisState {
            // 1. Selected sentence
            if let sentenceID = store.selectedSentenceID,
               let sentence = findSentence(id: sentenceID, in: snapshot) {
                return .sentence(id: sentence.id, range: sentence.range)
            }

            // 2. Selected paragraph
            if let paragraphID = store.selectedParagraphID,
               let paragraph = snapshot.paragraphs.first(where: { $0.id == paragraphID }) {
                return .paragraph(id: paragraph.id, range: paragraph.range)
            }
        }

        // 3. Explicit editor selection — works at any analysis state.
        if let range = store.selectedEditorRange, range.length > 0 {
            return .customSelection(range: range)
        }

        return nil
    }

    // MARK: - Helpers

    private static func findSentence(
        id: String,
        in snapshot: ReviewAnalysisSnapshot
    ) -> ReviewSentenceSnapshot? {
        for paragraph in snapshot.paragraphs {
            if let sentence = paragraph.sentences.first(where: { $0.id == id }) {
                return sentence
            }
        }
        return nil
    }
}
