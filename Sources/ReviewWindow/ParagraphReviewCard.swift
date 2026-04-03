// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI

public struct ParagraphReviewCard: View {
    let paragraph: ReviewParagraphSnapshot
    let issues: [WritingIssue]
    let isSelected: Bool
    let onSelectParagraph: () -> Void
    let onSelectSentence: (String) -> Void
    let onSelectIssue: (String) -> Void

    @State private var isExpanded: Bool = false

    public init(
        paragraph: ReviewParagraphSnapshot,
        issues: [WritingIssue],
        isSelected: Bool,
        onSelectParagraph: @escaping () -> Void,
        onSelectSentence: @escaping (String) -> Void,
        onSelectIssue: @escaping (String) -> Void
    ) {
        self.paragraph = paragraph
        self.issues = issues
        self.isSelected = isSelected
        self.onSelectParagraph = onSelectParagraph
        self.onSelectSentence = onSelectSentence
        self.onSelectIssue = onSelectIssue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            if isExpanded {
                sentenceList
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(spacing: 8) {
            Button(action: onSelectParagraph) {
                Text(paragraph.text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if !issues.isEmpty {
                issueBadge
            }

            Button(action: { isExpanded.toggle() }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var issueBadge: some View {
        Text("\(issues.count)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.accentColor)
            .clipShape(Capsule())
    }

    // MARK: - Sentence list

    private var sentenceList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider()
                .padding(.vertical, 4)
            ForEach(paragraph.sentences, id: \.id) { sentence in
                let sentenceIssues = issuesForSentence(sentence, allIssues: issues)
                Button {
                    onSelectSentence(sentence.id)
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Text(sentence.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !sentenceIssues.isEmpty {
                            HStack(spacing: 2) {
                                ForEach(sentenceIssues.prefix(3), id: \.id) { issue in
                                    Image(systemName: issue.type.icon)
                                        .font(.caption2)
                                        .foregroundStyle(issue.type.color)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func issuesForSentence(
        _ sentence: ReviewSentenceSnapshot,
        allIssues: [WritingIssue]
    ) -> [WritingIssue] {
        let idSet = Set(sentence.issueIDs)
        return allIssues.filter { idSet.contains($0.id) }
    }
}
