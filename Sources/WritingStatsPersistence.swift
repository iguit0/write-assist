// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import os

enum WritingStatsPersistence {
    static let legacyStorageKey = "writingSessions"

    static func defaultStorageURL(fileManager: FileManager = .default) -> URL? {
        guard let appSupportBase = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let appSupportDir = appSupportBase.appendingPathComponent("WriteAssist", isDirectory: true)
        do {
            try fileManager.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
            return appSupportDir.appendingPathComponent("writing-stats.json", isDirectory: false)
        } catch {
            return nil
        }
    }

    static func load(
        userDefaults: UserDefaults,
        storageURL: URL?,
        logger: Logger
    ) -> [WritingSession] {
        if let sessions = loadFromFile(storageURL: storageURL, logger: logger) {
            return sessions
        }

        guard let data = userDefaults.data(forKey: legacyStorageKey) else {
            return []
        }

        guard let sessions = try? JSONDecoder().decode([WritingSession].self, from: data) else {
            logger.error("Failed to decode legacy writing sessions from UserDefaults")
            return []
        }

        let migrated = saveToFile(sessions: sessions, storageURL: storageURL, logger: logger)
        if migrated {
            userDefaults.removeObject(forKey: legacyStorageKey)
        }

        return sessions
    }

    @discardableResult
    static func saveToFile(
        sessions: [WritingSession],
        storageURL: URL?,
        logger: Logger
    ) -> Bool {
        guard let storageURL else {
            logger.error("Writing stats storageURL unavailable")
            return false
        }

        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: storageURL, options: .atomic)
            return true
        } catch {
            logger.error("Failed to persist writing stats file: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func loadFromFile(storageURL: URL?, logger: Logger) -> [WritingSession]? {
        guard let storageURL,
              let data = try? Data(contentsOf: storageURL) else {
            return nil
        }

        guard let sessions = try? JSONDecoder().decode([WritingSession].self, from: data) else {
            logger.error("Failed to decode writing stats file at \(storageURL.path, privacy: .public)")
            return nil
        }

        return sessions
    }
}
