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
            ReviewEditorView(store: reviewStore)
                .navigationSplitViewColumnWidth(min: 300, ideal: 500, max: .infinity)
        } detail: {
            ReviewInspectorView(store: reviewStore)
                .navigationSplitViewColumnWidth(min: 200, ideal: 280)
        }
    }
}
