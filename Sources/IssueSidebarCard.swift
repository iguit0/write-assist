// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI

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
        issue.type.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 0) {
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

                                HStack(spacing: 3) {
                                    Image(systemName: issue.type.icon)
                                        .font(.system(size: 8))
                                    Text(issue.type.categoryLabel)
                                        .font(.system(size: 9, weight: .semibold))
                                }
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
