// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import Testing
@testable import WriteAssistCore

@Suite("WritingStatsStore")
struct WritingStatsStoreTests {
    @MainActor
    @Test("migrates legacy userdefaults sessions to file")
    func migratesLegacyData() throws {
        let suite = "stats-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        let session = WritingSession(
            id: UUID(),
            date: Date(),
            wordCount: 42,
            issuesByType: ["Spelling": 2],
            correctionsApplied: 1
        )
        let data = try JSONEncoder().encode([session])
        defaults.set(data, forKey: WritingStatsPersistence.legacyStorageKey)

        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("writing-stats-\(UUID().uuidString).json")

        let store = WritingStatsStore(userDefaults: defaults, storageURL: storageURL)

        #expect(store.sessions.count == 1)
        #expect(FileManager.default.fileExists(atPath: storageURL.path))
        #expect(defaults.data(forKey: WritingStatsPersistence.legacyStorageKey) == nil)
    }
}
