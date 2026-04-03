// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI

public struct ReviewWorkbenchView: View {
    let reviewStore: ReviewSessionStore
    let rewriteStore: RewriteSessionStore
    let onReview: () -> Void

    public init(reviewStore: ReviewSessionStore, rewriteStore: RewriteSessionStore, onReview: @escaping () -> Void) {
        self.reviewStore = reviewStore
        self.rewriteStore = rewriteStore
        self.onReview = onReview
    }

    public var body: some View {
        ReviewWorkbenchLayout(reviewStore: reviewStore, rewriteStore: rewriteStore)
            .navigationTitle("WriteAssist")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Review", action: onReview)
                }
            }
    }
}
