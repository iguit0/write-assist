// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI

enum ToolsTab: String, CaseIterable {
    case dictionary = "Dictionary"
    case stats = "Stats"
}

struct ToolsPanel: View {
    @State private var selectedTab: ToolsTab = .dictionary

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(ToolsTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                selectedTab == tab
                                    ? Color.accentColor.opacity(0.1)
                                    : Color.clear
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            switch selectedTab {
            case .dictionary:
                DictionaryView()
            case .stats:
                WritingStatsView()
            }
        }
    }
}

struct DictionaryView: View {
    @State private var dictionary = PersonalDictionary.shared
    @State private var newWord = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("Add word...", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { addWord() }

                Button(action: addWord) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if dictionary.words.isEmpty {
                VStack(spacing: 8) {
                    Spacer(minLength: 20)
                    Image(systemName: "book.closed")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("No custom words")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Words you add will be recognized by the spell checker.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer(minLength: 20)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(dictionary.words, id: \.self) { word in
                            HStack {
                                Text(word)
                                    .font(.system(size: 11))
                                Spacer()
                                Button {
                                    dictionary.removeWord(word)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
            }
        }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        dictionary.addWord(trimmed)
        newWord = ""
    }
}
