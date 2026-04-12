// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI

// MARK: - Main View

public struct ReviewSelectionPanelView: View {
    let panelStore: ReviewSelectionPanelStore
    let onOpenWorkspace: () -> Void
    let onAcceptRewrite: (String) -> Void
    let onDismiss: () -> Void

    public init(
        panelStore: ReviewSelectionPanelStore,
        onOpenWorkspace: @escaping () -> Void,
        onAcceptRewrite: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.panelStore = panelStore
        self.onOpenWorkspace = onOpenWorkspace
        self.onAcceptRewrite = onAcceptRewrite
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footerLink
        }
        .frame(width: 320)
        .fixedSize(horizontal: true, vertical: true)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var content: some View {
        switch panelStore.phase {
        case .idle, .importing:
            PanelImportingView()
        case .error(let error):
            PanelErrorView(error: error, onDismiss: onDismiss)
        case .review:
            reviewContent
        }
    }

    @ViewBuilder
    private var reviewContent: some View {
        let rewriteState = panelStore.rewriteStore.rewriteState
        VStack(spacing: 12) {
            PanelTextPreview(
                text: previewText,
                sourceApp: panelStore.importedSelection?.metadata.appName
            )
            switch rewriteState {
            case .idle, .failed:
                PanelActionButtonGrid(
                    issueCount: issueCount,
                    activeMode: panelStore.activeRewriteMode,
                    isRewriting: false,
                    onTapMode: { mode in
                        panelStore.requestRewrite(mode: mode)
                    }
                )
            case .rewriting:
                PanelActionButtonGrid(
                    issueCount: issueCount,
                    activeMode: panelStore.activeRewriteMode,
                    isRewriting: true,
                    onTapMode: { _ in }
                )
            case .ready(let candidates, _, _):
                if let candidate = candidates.first {
                    PanelRewriteResult(
                        originalText: previewText,
                        rewrittenText: candidate.text,
                        onAccept: { onAcceptRewrite(candidate.text) },
                        onReject: { panelStore.rejectRewrite() }
                    )
                }
            }
        }
        .padding(16)
    }

    private var footerLink: some View {
        Button {
            onOpenWorkspace()
        } label: {
            HStack(spacing: 4) {
                Text("Open in Workspace")
                    .font(.caption)
                Image(systemName: "arrow.right")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private var previewText: String {
        let text = panelStore.importedSelection?.text ?? panelStore.reviewStore.document.text
        return text.isEmpty ? "No text imported yet." : text
    }

    private var issueCount: Int {
        guard case .ready(let snapshot) = panelStore.reviewStore.analysisState else { return 0 }
        return snapshot.issues.count
    }
}

// MARK: - Importing View

struct PanelImportingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text("Importing selected text…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

// MARK: - Error View

struct PanelErrorView: View {
    let error: SelectionImportError
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.orange)
            Text(error.userFacingMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

// MARK: - Text Preview

struct PanelTextPreview: View {
    let text: String
    let sourceApp: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
            if let sourceApp {
                Text("From: \(sourceApp)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 10))
    }
}

// MARK: - Action Button Grid

struct PanelActionButtonGrid: View {
    let issueCount: Int
    let activeMode: RewriteMode?
    let isRewriting: Bool
    let onTapMode: (RewriteMode) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(RewriteMode.allCases, id: \.rawValue) { mode in
                modeButton(mode)
            }
        }
    }

    private func modeButton(_ mode: RewriteMode) -> some View {
        Button {
            onTapMode(mode)
        } label: {
            HStack(spacing: 4) {
                if isRewriting && activeMode == mode {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                } else {
                    Text(mode.label)
                        .font(.subheadline.weight(.medium))
                }
                if mode == .grammarFix && issueCount > 0 && !(isRewriting && activeMode == mode) {
                    Text("\(issueCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.red, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isRewriting)
        .opacity(isRewriting && activeMode != mode ? 0.5 : 1.0)
        .accessibilityLabel(accessibilityLabel(for: mode))
    }

    private func accessibilityLabel(for mode: RewriteMode) -> String {
        if mode == .grammarFix && issueCount > 0 {
            return "\(mode.label), \(issueCount) issue\(issueCount == 1 ? "" : "s") found"
        }
        return mode.label
    }
}

// MARK: - Rewrite Result

struct PanelRewriteResult: View {
    let originalText: String
    let rewrittenText: String
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(rewrittenText)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.green.opacity(0.08), in: .rect(cornerRadius: 10))

            HStack(spacing: 8) {
                Button {
                    onAccept()
                } label: {
                    Label("Accept", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)

                Button {
                    onReject()
                } label: {
                    Label("Reject", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
