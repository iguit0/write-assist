// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI

/// A compact toolbar below the editor that lets the user pick a rewrite mode
/// and trigger an explicit rewrite of the selected sentence/paragraph/selection.
public struct RewriteToolbar: View {
    let reviewStore: ReviewSessionStore
    @Bindable var rewriteStore: RewriteSessionStore

    public init(reviewStore: ReviewSessionStore, rewriteStore: RewriteSessionStore) {
        self.reviewStore = reviewStore
        self.rewriteStore = rewriteStore
    }

    public var body: some View {
        HStack(spacing: 8) {
            modePicker
            Spacer()
            statusLabel
            rewriteButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        Picker("Mode", selection: $rewriteStore.selectedMode) {
            ForEach(RewriteMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
        .disabled(rewriteStore.isRewriting)
    }

    // MARK: - Status label

    @ViewBuilder
    private var statusLabel: some View {
        switch rewriteStore.rewriteState {
        case .rewriting:
            HStack(spacing: 4) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                Text("Rewriting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let msg, _):
            Text(msg)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        default:
            EmptyView()
        }
    }

    // MARK: - Rewrite button

    private var rewriteButton: some View {
        HStack(spacing: 4) {
            if rewriteStore.isRewriting {
                Button("Cancel") {
                    rewriteStore.rejectCandidates()
                }
                .foregroundStyle(.secondary)
            } else {
                Button {
                    rewriteStore.requestRewrite(mode: rewriteStore.selectedMode, from: reviewStore)
                } label: {
                    Label("Rewrite", systemImage: "sparkles")
                }
                .disabled(!hasTarget)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Helpers

    private var hasTarget: Bool {
        RewriteTargetResolver.resolve(from: reviewStore) != nil
    }
}
