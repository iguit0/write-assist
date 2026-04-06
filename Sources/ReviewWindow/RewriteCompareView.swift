// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI

/// Shows original text vs rewrite candidates with accept / reject / regenerate actions.
/// Appears in the inspector panel while a rewrite is in progress or ready.
public struct RewriteCompareView: View {
    let reviewStore: ReviewSessionStore
    let rewriteStore: RewriteSessionStore

    public init(reviewStore: ReviewSessionStore, rewriteStore: RewriteSessionStore) {
        self.reviewStore = reviewStore
        self.rewriteStore = rewriteStore
    }

    public var body: some View {
        switch rewriteStore.rewriteState {
        case .rewriting:
            loadingView
        case .ready(let candidates, let target, _):
            readyView(candidates: candidates, target: target)
        case .failed(let message, _):
            failedView(message: message)
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Rewriting…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Ready

    private func readyView(candidates: [RewriteCandidate], target: RewriteTarget) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Rewrite Suggestion", systemImage: "sparkles")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 12)

                // Original
                GroupBox("Original") {
                    Text(originalText(for: target))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(.horizontal)

                // Candidate
                if let candidate = candidates.first {
                    GroupBox("Suggested") {
                        Text(candidate.text)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal)

                    Text(candidate.modelName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal)

                    actionButtons(candidateID: candidate.id)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func actionButtons(candidateID: UUID) -> some View {
        VStack(spacing: 8) {
            Button {
                rewriteStore.acceptCandidate(id: candidateID, applying: reviewStore)
            } label: {
                Label("Accept", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.horizontal)

            HStack(spacing: 8) {
                Button {
                    rewriteStore.rejectCandidates()
                } label: {
                    Label("Reject", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    rewriteStore.requestRewrite(mode: rewriteStore.selectedMode, from: reviewStore)
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Failed

    private func failedView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.orange)
            Text("Rewrite failed")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Dismiss") {
                rewriteStore.rejectCandidates()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func originalText(for target: RewriteTarget) -> String {
        let nsText = reviewStore.document.text as NSString
        let range = target.nsRange
        guard range.location != NSNotFound,
              range.location + range.length <= nsText.length else {
            return ""
        }
        return nsText.substring(with: range)
    }
}
