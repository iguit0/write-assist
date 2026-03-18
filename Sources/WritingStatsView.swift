// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI

struct WritingStatsView: View {
    @State private var stats = WritingStatsStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                statsSection(title: "Current Session") {
                    HStack(spacing: 16) {
                        statItem(label: "Words", value: "\(stats.currentSessionWordCount)")
                        statItem(label: "Corrections", value: "\(stats.currentSessionCorrections)")
                    }
                }

                statsSection(title: "This Week") {
                    HStack(spacing: 16) {
                        statItem(label: "Words", value: "\(stats.wordsThisWeek)")
                        statItem(label: "Sessions", value: "\(stats.sessionsThisWeek.count)")
                    }
                }

                statsSection(title: "All Time") {
                    HStack(spacing: 16) {
                        statItem(label: "Words", value: "\(stats.totalWordsWritten)")
                        statItem(label: "Corrections", value: "\(stats.totalCorrections)")
                        statItem(label: "Sessions", value: "\(stats.sessions.count)")
                    }
                }

                if !stats.topRecurringIssues.isEmpty {
                    statsSection(title: "Top Issues") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(stats.topRecurringIssues, id: \.type) { item in
                                HStack {
                                    Text(item.type)
                                        .font(.system(size: 10))
                                    Spacer()
                                    Text("\(item.count)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 380)
    }

    private func statsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }
}
