// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI

public struct ReviewWorkbenchLayout: View {
    let reviewStore: ReviewSessionStore
    let rewriteStore: RewriteSessionStore

    public init(reviewStore: ReviewSessionStore, rewriteStore: RewriteSessionStore) {
        self.reviewStore = reviewStore
        self.rewriteStore = rewriteStore
    }

    public var body: some View {
        NavigationSplitView {
            ParagraphReviewList(store: reviewStore)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            VStack(spacing: 0) {
                ReviewEditorView(store: reviewStore)
                Divider()
                RewriteToolbar(reviewStore: reviewStore, rewriteStore: rewriteStore)
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 500, max: .infinity)
        } detail: {
            detailPanel
                .navigationSplitViewColumnWidth(min: 220, ideal: 300)
        }
    }

    // MARK: - Detail panel

    /// Shows the rewrite compare view when a rewrite is in progress or ready;
    /// falls back to the issue inspector otherwise.
    @ViewBuilder
    private var detailPanel: some View {
        switch rewriteStore.rewriteState {
        case .idle:
            ReviewInspectorView(store: reviewStore)
        case .rewriting, .ready, .failed:
            RewriteCompareView(reviewStore: reviewStore, rewriteStore: rewriteStore)
        }
    }
}
