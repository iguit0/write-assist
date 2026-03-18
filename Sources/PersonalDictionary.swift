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
    private let fileURL = PersonalDictionary.dictionaryFileURL

    private static let dictionaryFileURL: URL? = {
        let fileManager = FileManager.default
        guard let appSupportBase = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }

        let appSupportDir = appSupportBase.appendingPathComponent("WriteAssist", isDirectory: true)
        do {
            try fileManager.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
            return appSupportDir.appendingPathComponent("personal-dictionary.json", isDirectory: false)
        } catch {
            logger.error("Failed to create Application Support dir: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    private init() {
        // Canonical source can come from either UserDefaults or persisted file.
        // This helps survive app reinstalls where defaults may be wiped.
        let defaultsWords = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        let fileWords = loadWordsFromFile()

        words = Self.normalized(defaultsWords + fileWords)
        persist()

        // Ensure all canonical words are learned by NSSpellChecker.
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
        words = Self.normalized(words)
        persist()

        NSSpellChecker.shared.learnWord(lower)
        logger.info("Learned word: '\(lower)'")
    }

    func removeWord(_ word: String) {
        let lower = word.lowercased()
        words.removeAll { $0 == lower }
        persist()

        NSSpellChecker.shared.unlearnWord(lower)
        logger.info("Unlearned word: '\(lower)'")
    }

    func containsWord(_ word: String) -> Bool {
        words.contains(word.lowercased())
    }

    private func persist() {
        UserDefaults.standard.set(words, forKey: storageKey)
        saveWordsToFile(words)
    }

    private func loadWordsFromFile() -> [String] {
        guard let fileURL else { return [] }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            logger.error("Failed to decode personal dictionary file at \(fileURL.path, privacy: .public)")
            return []
        }
        return decoded
    }

    private func saveWordsToFile(_ words: [String]) {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(words)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save personal dictionary file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func normalized(_ input: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for word in input {
            let lower = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !lower.isEmpty else { continue }
            if seen.insert(lower).inserted {
                output.append(lower)
            }
        }

        return output.sorted()
    }
}
