// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.
// LEGACY — Non-primary. Part of the ambient inline-monitor path superseded by the Review
// Workbench. No new product behavior should be added here.

import SwiftUI

/// SwiftUI content for `SelectionSuggestionPanel`.
///
/// Shows a compact popup with:
/// - A horizontal tab bar (Improve, Rephrase, Shorten, Formal, Friendly)
/// - A suggestion area — diff view for Improve, plain text for others
/// - An Accept button that applies the current suggestion to the focused app
///
/// The view observes `SelectionSuggestionState` (an `@Observable` class owned
/// by the panel) and calls back through closures for all actions.
struct SelectionSuggestionView: View {
    let state: SelectionSuggestionState
    let onAccept: () -> Void
    let onDismiss: () -> Void
    let onTabSelected: (SuggestionTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabBarRow
            Divider()
                .padding(.horizontal, 2)
            contentArea
                .padding(12)
                .frame(minHeight: 64)
            Divider()
                .padding(.horizontal, 2)
            actionRow
        }
        .frame(width: 400)
        // fixedSize tells SwiftUI to use its ideal (intrinsic) height rather than
        // expanding to fill the container. This makes NSHostingView.fittingSize
        // return the true content height, which resizePanelIfNeeded() relies on.
        .fixedSize(horizontal: true, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
        .padding(2) // prevents shadow clipping
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rewrite suggestions")
        .accessibilityHint("Use the tabs to generate a rewrite, then press Accept to apply")
    }

    // MARK: - Tab Bar

    private var tabBarRow: some View {
        HStack(spacing: 0) {
            // Tabs fill available space, scrolling only when screen is very narrow.
            // `.never` avoids the scroll-indicator bar that would appear beneath tabs.
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(SuggestionTab.allCases, id: \.self) { tab in
                        tabPill(tab)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.never)
            .accessibilityLabel("Rewrite styles")

            // Dismiss button anchored to the right of the tab row
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(4)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .padding(.trailing, 10)
        }
    }

    private func tabPill(_ tab: SuggestionTab) -> some View {
        let isActive = state.activeTab == tab
        return Button {
            onTabSelected(tab)
        } label: {
            Text(tab.label)
                // Slightly smaller font + tighter horizontal padding so all 5 tabs
                // fit in 340pt without needing to scroll on a standard-sized panel.
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isActive ? Color.accentColor : Color.primary.opacity(0.06))
                )
                .foregroundStyle(isActive ? .white : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityHint(tab.descriptionLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .animation(.easeInOut(duration: 0.15), value: state.activeTab)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if state.loadingTabs.contains(state.activeTab) {
            loadingView
        } else if let result = state.tabResults[state.activeTab] {
            resultView(result: result)
        } else if let error = state.errorMessage {
            errorView(message: error)
        } else {
            emptyStateView
        }
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
                Text(state.activeTab.loadingLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            cloudDisclosure
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func resultView(result: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.activeTab.descriptionLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.green)

            if state.activeTab == .improve {
                diffView(original: state.selectedText, suggestion: result)
            } else {
                plainResultView(text: result)
            }
        }
    }

    /// Diff display for the Improve tab: original text with strikethrough + suggestion in teal.
    private func diffView(original: String, suggestion: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(original)
                .font(.system(size: 13))
                .strikethrough(true, color: .secondary)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(suggestion)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.08, green: 0.62, blue: 0.52))
                .lineLimit(3)
                // textSelection(.enabled) wraps Text in an NSScrollView on macOS,
                // which reports zero intrinsicContentSize and breaks fittingSize.
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Suggested rewrite")
        .accessibilityValue("Original: \(original). Suggestion: \(suggestion)")
    }

    private func plainResultView(text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .lineLimit(4)
            // textSelection(.enabled) removed — it wraps Text in an NSScrollView
            // whose intrinsicContentSize is zero, collapsing the panel on resize.
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Suggested rewrite")
            .accessibilityValue(text)
    }

    private func errorView(message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.red.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Click a style above to generate a rewrite.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            cloudDisclosure
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack {
            // Selected-text preview (truncated) as a subtle hint
            Text(state.selectedText)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 260, alignment: .leading)

            Spacer(minLength: 8)

            Button("Accept") {
                onAccept()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(state.tabResults[state.activeTab] == nil)
            .accessibilityLabel("Accept \(state.activeTab.label.lowercased()) rewrite")
            .accessibilityHint("Replaces your selected text with the AI suggestion")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var cloudDisclosure: some View {
        Text("Uses your configured AI provider only after you click a style.")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
