// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import SwiftUI

// MARK: - Menu Bar Popover Root View

struct MenuBarPopoverView: View {
    var viewModel: DocumentViewModel
    var inputMonitor: GlobalInputMonitor
    @State private var animateIn = false
    @State private var isPreviewExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            popoverHeader
            Divider()

            if !inputMonitor.hasAccessibilityPermission {
                accessibilityPrompt
            } else {
                issuesList
            }
        }
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var popoverHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .foregroundStyle(.tint)
                .font(.system(size: 14, weight: .medium))

            Text("WriteAssist")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            // Word count
            if viewModel.wordCount > 0 {
                HStack(spacing: 3) {
                    Text("\(viewModel.wordCount)")
                        .font(.system(size: 11, weight: .medium))
                    Text("words")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Score badge
            ScoreBadge(score: viewModel.writingScore)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Preview Panel

    private var previewPanel: some View {
        VStack(spacing: 0) {
            // Collapsible header
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
                    if !viewModel.issues.filter({ !$0.isIgnored }).isEmpty {
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
                HighlightedTextView(text: viewModel.text, issues: viewModel.issues)
                    .frame(height: min(max(CGFloat(viewModel.text.count) / 4 + 48, 56), 110))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }

    // MARK: - Issues List

    private var issuesList: some View {
        VStack(spacing: 0) {
            // Issue count chips
            if viewModel.spellingCount > 0 || viewModel.grammarCount > 0 {
                HStack(spacing: 8) {
                    if viewModel.spellingCount > 0 {
                        issueChip(count: viewModel.spellingCount, label: "spelling", color: .red)
                    }
                    if viewModel.grammarCount > 0 {
                        issueChip(count: viewModel.grammarCount, label: "grammar", color: .orange)
                    }
                    Spacer()

                    // Clear buffer button
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

            // Text preview panel — shown when there's captured text.
            // Only prepend a divider when the chips strip above wasn't shown
            // (which already has its own trailing divider).
            if !viewModel.text.isEmpty {
                let hasChips = viewModel.spellingCount > 0 || viewModel.grammarCount > 0
                if !hasChips {
                    Divider()
                }
                previewPanel
                Divider()
            }

            let active = viewModel.issues.filter { !$0.isIgnored }

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

            Divider()
            popoverFooter
        }
    }

    // MARK: - Empty State

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

    // MARK: - Accessibility Prompt

    private var accessibilityPrompt: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 16)

            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text("Accessibility Access Required")
                .font(.system(size: 13, weight: .semibold))

            Text("WriteAssist needs Accessibility permission to monitor your typing across all apps.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Enable Access") {
                inputMonitor.requestPermission()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    private var popoverFooter: some View {
        HStack {
            // Monitoring status indicator
            HStack(spacing: 5) {
                Circle()
                    .fill(inputMonitor.hasAccessibilityPermission ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(inputMonitor.hasAccessibilityPermission ? "Monitoring" : "Not active")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Quit button
            Button("Quit WriteAssist") {
                NSApp.terminate(nil)
            }
            .font(.system(size: 10))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

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

// MARK: - Score Badge

struct ScoreBadge: View {
    let score: Int

    private var color: Color {
        switch score {
        case 85...100: return .green
        case 60..<85:  return .orange
        default:        return .red
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 3)
                .frame(width: 32, height: 32)

            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 32, height: 32)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: score)

            Text("\(score)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Issue Sidebar Card

struct IssueSidebarCard: View {
    let issue: WritingIssue
    let isNew: Bool
    let onApply: (String) -> Void
    let onIgnore: () -> Void

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var copiedSuggestion: String?
    @State private var pulsing = false

    private var accentColor: Color {
        issue.type == .spelling ? .red : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 0) {
                    // Thick accent bar with gradient
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 4)
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: 8,
                            bottomLeadingRadius: 8,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        ))

                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(issue.word)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)

                                // "NEW" dot for unseen issues
                                if isNew {
                                    Circle()
                                        .fill(accentColor)
                                        .frame(width: 6, height: 6)
                                        .scaleEffect(pulsing ? 1.4 : 1.0)
                                        .opacity(pulsing ? 0.6 : 1.0)
                                        .animation(
                                            .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                            value: pulsing
                                        )
                                }

                                Spacer()

                                // Issue type chip
                                Text(issue.type == .spelling ? "Spelling" : "Grammar")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(accentColor)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(accentColor.opacity(0.12))
                                    .clipShape(Capsule())

                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }

                            Text(issue.message)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded: suggestions
            if isExpanded {
                Divider()
                    .padding(.leading, 24)

                VStack(alignment: .leading, spacing: 2) {
                    if issue.suggestions.isEmpty {
                        Text("No suggestions available")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(issue.suggestions.prefix(4), id: \.self) { suggestion in
                            Button {
                                onApply(suggestion)
                                copiedSuggestion = suggestion
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(1500))
                                    if copiedSuggestion == suggestion {
                                        copiedSuggestion = nil
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: copiedSuggestion == suggestion
                                          ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(copiedSuggestion == suggestion ? .green : accentColor)
                                    Text(copiedSuggestion == suggestion ? "Applied ✓" : suggestion)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(copiedSuggestion == suggestion ? .green : .primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    copiedSuggestion == suggestion
                                        ? Color.green.opacity(0.08)
                                        : Color.clear
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: copiedSuggestion)
                        }
                    }

                    Divider()
                        .padding(.leading, 14)

                    Button(action: onIgnore) {
                        HStack(spacing: 5) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 10))
                            Text("Dismiss")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isHovered
                        ? accentColor.opacity(0.04)
                        : Color(nsColor: .textBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isNew ? accentColor.opacity(pulsing ? 0.5 : 0.2) : Color.clear,
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: .black.opacity(isHovered ? 0.1 : 0.05),
                    radius: isHovered ? 4 : 2,
                    y: 1
                )
        )
        .scaleEffect(isHovered ? 1.005 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear {
            if isNew {
                pulsing = true
            }
        }
    }
}
