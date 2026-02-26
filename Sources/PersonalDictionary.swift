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
        // Load from UserDefaults and migrate to lowercase for case-insensitive lookup
        let loaded = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        var seen = Set<String>()
        var migrated: [String] = []
        for word in loaded {
            let lower = word.lowercased()
            if seen.insert(lower).inserted {
                migrated.append(lower)
            }
        }
        words = migrated.sorted()
        // Persist migration if any words changed casing or were deduplicated
        if migrated.count != loaded.count || zip(migrated, loaded).contains(where: { $0 != $1 }) {
            UserDefaults.standard.set(words, forKey: storageKey)
        }
        // Ensure all words are learned by NSSpellChecker
        let checker = NSSpellChecker.shared
        for word in words {
            checker.learnWord(word)
        }
        logger.info("PersonalDictionary loaded \(self.words.count) words")
    }

    func addWord(_ word: String) {
        let lower = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty, !words.contains(lower) else { return }
        words.append(lower)
        words.sort()
        save()
        NSSpellChecker.shared.learnWord(lower)
        logger.info("Learned word: '\(lower)'")
    }

    func removeWord(_ word: String) {
        let lower = word.lowercased()
        words.removeAll { $0 == lower }
        save()
        NSSpellChecker.shared.unlearnWord(lower)
        logger.info("Unlearned word: '\(lower)'")
    }

    func containsWord(_ word: String) -> Bool {
        words.contains(word.lowercased())
    }

    private func save() {
        UserDefaults.standard.set(words, forKey: storageKey)
    }
}
