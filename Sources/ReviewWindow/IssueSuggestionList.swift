// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI

public struct IssueSuggestionList: View {
    let suggestions: [String]
    let onApply: (String) -> Void

    public init(suggestions: [String], onApply: @escaping (String) -> Void) {
        self.suggestions = suggestions
        self.onApply = onApply
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggestions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    onApply(suggestion)
                } label: {
                    HStack {
                        Text(suggestion)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
