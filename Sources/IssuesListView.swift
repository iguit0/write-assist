// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI

struct IssuesListView: View {
    let viewModel: DocumentViewModel
    let inputMonitor: GlobalInputMonitor

    @State private var isPreviewExpanded = true
    @State private var isMetricsExpanded = false
    @State private var selectedCategory: IssueCategory?
    @State private var selectedTextForSuggestions: String?

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.totalActiveIssueCount > 0 {
                HStack(spacing: 8) {
                    if viewModel.spellingCount > 0 {
                        issueChip(count: viewModel.spellingCount, label: "spelling", color: .red)
                    }
                    if viewModel.grammarCount > 0 {
                        issueChip(count: viewModel.grammarCount, label: "grammar", color: .orange)
                    }
                    if viewModel.clarityCount > 0 {
                        issueChip(count: viewModel.clarityCount, label: "clarity", color: .blue)
                    }
                    if viewModel.engagementCount > 0 {
                        issueChip(count: viewModel.engagementCount, label: "engagement", color: .purple)
                    }
                    if viewModel.styleCount > 0 {
                        issueChip(count: viewModel.styleCount, label: "style", color: .green)
                    }
                    Spacer()

                    Button {
                        inputMonitor.clearBuffer()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear captured text")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
            }

            if viewModel.wordCount > 0 {
                metricsDrawer
                Divider()
            }

            if !viewModel.text.isEmpty {
                previewPanel

                if let selectedTextForSuggestions, !selectedTextForSuggestions.isEmpty {
                    Divider()
                    TextSelectionSuggestionsPanel(
                        selectedText: selectedTextForSuggestions,
                        onCopy: { suggestion in
                            PasteboardTransaction.write(suggestion)
                            self.selectedTextForSuggestions = nil
                        },
                        onDismiss: {
                            self.selectedTextForSuggestions = nil
                        }
                    )
                }

                Divider()
            }

            if viewModel.totalActiveIssueCount > 0 {
                categoryFilterChips
                Divider()
            }

            let active = selectedCategory.map { category in
                viewModel.issues.filter { $0.type.category == category }
            } ?? viewModel.issues

            if active.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(active) { issue in
                            IssueSidebarCard(
                                issue: issue,
                                isNew: viewModel.unseenIssueIDs.contains(issue.id),
                                onApply: { correction in
                                    viewModel.applyCorrection(issue, correction: correction)
                                },
                                onIgnore: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.ignoreIssue(issue)
                                    }
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: active.map(\.id))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 380)
            }
        }
    }

    private var metricsDrawer: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isMetricsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isMetricsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Metrics")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isMetricsExpanded {
                metricsContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }

    private var metricsContent: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                metricItem(
                    label: "Readability",
                    value: String(format: "%.0f", viewModel.readabilityScore),
                    icon: "book.fill",
                    color: viewModel.readabilityScore >= 60 ? .green : (viewModel.readabilityScore >= 30 ? .orange : .red)
                )
                metricItem(
                    label: "Read time",
                    value: formatTime(viewModel.readingTime),
                    icon: "clock",
                    color: .blue
                )
                metricItem(
                    label: "Speak time",
                    value: formatTime(viewModel.speakingTime),
                    icon: "mic",
                    color: .purple
                )
            }

            HStack(spacing: 12) {
                metricItem(
                    label: "Sentences",
                    value: "\(viewModel.sentenceCount)",
                    icon: "text.alignleft",
                    color: .secondary
                )
                metricItem(
                    label: "Avg length",
                    value: String(format: "%.1f", viewModel.averageSentenceLength),
                    icon: "ruler",
                    color: .secondary
                )
                metricItem(
                    label: "Vocab",
                    value: String(format: "%.0f%%", viewModel.vocabularyDiversity * 100),
                    icon: "textformat.abc",
                    color: viewModel.vocabularyDiversity >= 0.7 ? .green : .orange
                )
            }

            HStack(spacing: 6) {
                Image(systemName: viewModel.detectedTone.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.tint)
                Text("Tone:")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(viewModel.detectedTone.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func metricItem(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatTime(_ minutes: Double) -> String {
        if minutes < 1 {
            return "<1m"
        } else if minutes < 60 {
            return String(format: "%.0fm", minutes)
        } else {
            let h = Int(minutes / 60)
            let m = Int(minutes.truncatingRemainder(dividingBy: 60))
            return "\(h)h\(m)m"
        }
    }

    private var previewPanel: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPreviewExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isPreviewExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Text Preview")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !viewModel.issues.isEmpty {
                        let sc = viewModel.spellingCount
                        let gc = viewModel.grammarCount
                        HStack(spacing: 4) {
                            if sc > 0 {
                                Text("\(sc) spell")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.red)
                            }
                            if gc > 0 {
                                Text("\(gc) grammar")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isPreviewExpanded {
                HighlightedTextView(
                    text: viewModel.text,
                    issues: viewModel.issues,
                    onSelectionChanged: { selectedText, _ in
                        selectedTextForSuggestions = selectedText
                    }
                )
                .frame(height: min(max(CGFloat(viewModel.text.count) / 4 + 48, 56), 110))
                .overlay(alignment: .topLeading) {
                    if viewModel.text.isEmpty {
                        if #available(macOS 14.0, *) {
                            EmptyView()
                        } else {
                            Text("Type or paste your text here…")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }

    private var categoryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(label: "All", category: nil, count: viewModel.totalActiveIssueCount)

                ForEach(IssueCategory.allCases, id: \.self) { category in
                    let count = viewModel.issues.filter { $0.type.category == category }.count
                    if count > 0 {
                        categoryChip(label: category.rawValue, category: category, count: count)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func categoryChip(label: String, category: IssueCategory?, count: Int) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(isSelected ? (category?.color ?? .primary) : Color.secondary.opacity(0.15))
                    )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isSelected ? (category?.color ?? .primary).opacity(0.15) : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? (category?.color ?? .primary).opacity(0.3) : Color.secondary.opacity(0.15),
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 20)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)

            Text("Looking good!")
                .font(.system(size: 13, weight: .semibold))

            Text(viewModel.text.isEmpty
                 ? "Start typing anywhere — WriteAssist is watching."
                 : "No issues found in your recent text.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func issueChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}
