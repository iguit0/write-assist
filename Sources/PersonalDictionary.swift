// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import os

private let logger = Logger(subsystem: "com.writeassist", category: "PersonalDictionary")

@MainActor
@Observable
final class PersonalDictionary: @unchecked Sendable {
    static let shared = PersonalDictionary()

    private(set) var words: [String] = []
    private let storageKey = "personalDictionaryWords"

    private init() {
        // Load from UserDefaults
        words = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        // Ensure all words are learned by NSSpellChecker
        let checker = NSSpellChecker.shared
        for word in words {
            checker.learnWord(word)
        }
        logger.info("PersonalDictionary loaded \(self.words.count) words")
    }

    func addWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !words.contains(trimmed) else { return }
        words.append(trimmed)
        words.sort()
        save()
        NSSpellChecker.shared.learnWord(trimmed)
        logger.info("Learned word: '\(trimmed)'")
    }

    func removeWord(_ word: String) {
        words.removeAll { $0 == word }
        save()
        NSSpellChecker.shared.unlearnWord(word)
        logger.info("Unlearned word: '\(word)'")
    }

    func containsWord(_ word: String) -> Bool {
        words.contains(word)
    }

    private func save() {
        UserDefaults.standard.set(words, forKey: storageKey)
    }
}
