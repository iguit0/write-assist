// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI

struct TextSelectionSuggestionsPanel: View {
    let selectedText: String
    let onCopy: (String) -> Void
    let onDismiss: () -> Void

    @State private var aiService = CloudAIService.shared
    @State private var suggestions: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var copiedSuggestion: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                Text("AI Suggestions")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Getting suggestions...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            } else if let error = errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Error")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            } else if suggestions.isEmpty {
                Text("No suggestions available")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Click a suggestion to copy it. Passive spell checks stay local.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                    ForEach(suggestions.prefix(3), id: \.self) { suggestion in
                        SuggestionButton(
                            suggestion: suggestion,
                            isApplied: copiedSuggestion == suggestion,
                            onTap: {
                                copiedSuggestion = suggestion
                                onCopy(suggestion)
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(800))
                                    onDismiss()
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            fetchSuggestions()
        }
    }

    private func fetchSuggestions() {
        guard aiService.isConfigured else {
            errorMessage = "AI is not configured. Add an API key in Settings."
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let issue = WritingIssue(
                    type: .style,
                    ruleID: "formality",
                    range: NSRange(location: 0, length: selectedText.count),
                    word: String(selectedText.prefix(20)),
                    message: "Improve this selection",
                    suggestions: []
                )

                let fetchedSuggestions = try await aiService.smartSuggestions(
                    for: issue,
                    context: selectedText
                )
                suggestions = fetchedSuggestions
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct SuggestionButton: View {
    let suggestion: String
    let isApplied: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: isApplied ? "checkmark.circle.fill" : "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(isApplied ? .green : .blue)

                Text(suggestion)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isApplied ? .green : .primary)
                    .lineLimit(2)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        isApplied
                            ? Color.green.opacity(0.1)
                            : isHovered
                            ? Color.blue.opacity(0.08)
                            : Color.clear
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isApplied)
    }
}
