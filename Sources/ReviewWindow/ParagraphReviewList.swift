// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI

public struct ParagraphReviewList: View {
    let store: ReviewSessionStore

    public init(store: ReviewSessionStore) {
        self.store = store
    }

    public var body: some View {
        switch store.analysisState {
        case .idle:
            EmptyStateView()
        case .analyzing:
            analyzingView
        case .ready(let snapshot):
            paragraphList(snapshot: snapshot)
        }
    }

    // MARK: - Subviews

    private var analyzingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text("Analyzing…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func paragraphList(snapshot: ReviewAnalysisSnapshot) -> some View {
        List(snapshot.paragraphs, id: \.id) { paragraph in
            ParagraphReviewCard(
                paragraph: paragraph,
                issues: issuesForParagraph(paragraph, in: snapshot),
                isSelected: store.selectedParagraphID == paragraph.id,
                onSelectParagraph: { store.selectParagraph(id: paragraph.id) },
                onSelectSentence: { sentenceID in store.selectSentence(id: sentenceID) },
                onSelectIssue: { issueID in store.selectIssue(id: issueID) }
            )
            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    // MARK: - Helpers

    private func issuesForParagraph(
        _ paragraph: ReviewParagraphSnapshot,
        in snapshot: ReviewAnalysisSnapshot
    ) -> [WritingIssue] {
        let idSet = Set(paragraph.issueIDs)
        return snapshot.issues.filter { idSet.contains($0.id) }
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Run Review to see results")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
