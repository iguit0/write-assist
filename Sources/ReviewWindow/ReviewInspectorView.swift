// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI

public struct ReviewInspectorView: View {
    let store: ReviewSessionStore

    public init(store: ReviewSessionStore) {
        self.store = store
    }

    public var body: some View {
        if let issue = selectedIssue {
            IssueDetailView(
                issue: issue,
                onApply: { suggestion in
                    store.applyReplacement(range: issue.range, replacement: suggestion)
                },
                onIgnore: {
                    store.ignoreIssue(id: issue.id)
                }
            )
        } else {
            EmptyInspectorView()
        }
    }

    private var selectedIssue: WritingIssue? {
        guard let id = store.selectedIssueID,
              case .ready(let snapshot) = store.analysisState else { return nil }
        return snapshot.issues.first { $0.id == id }
    }
}

// MARK: - Private subviews

private struct EmptyInspectorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Select an issue to inspect")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct IssueDetailView: View {
    let issue: WritingIssue
    let onApply: (String) -> Void
    let onIgnore: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IssueHeaderRow(issue: issue)
                IssueWordBadge(issue: issue)
                Text(issue.message)
                    .foregroundStyle(.secondary)
                    .font(.body)
                if !issue.suggestions.isEmpty {
                    IssueSuggestionList(suggestions: issue.suggestions, onApply: onApply)
                }
                Button("Dismiss") {
                    onIgnore()
                }
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }
}

private struct IssueHeaderRow: View {
    let issue: WritingIssue

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: issue.type.icon)
                .foregroundStyle(issue.type.color)
            Text(issue.type.categoryLabel)
                .font(.headline)
        }
    }
}

private struct IssueWordBadge: View {
    let issue: WritingIssue

    var body: some View {
        Text(issue.word)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(issue.type.color.opacity(0.12))
            .clipShape(.rect(cornerRadius: 6))
    }
}
