// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import Testing
@testable import WriteAssistCore

@Suite("PersonalDictionary")
struct PersonalDictionaryTests {
    @MainActor
    @Test("startup reconciles file and defaults stores")
    func startupReconciles() throws {
        let suite = "pd-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("writeassist-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("dictionary.json")

        defaults.set(["foo"], forKey: "personalDictionaryWords")
        let fileData = try JSONEncoder().encode(["bar"])
        try fileData.write(to: fileURL)

        let dictionary = PersonalDictionary(userDefaults: defaults, fileURL: fileURL)

        #expect(dictionary.words.contains("foo"))
        #expect(dictionary.words.contains("bar"))
    }
}
