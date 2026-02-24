// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import os

private let logger = Logger(subsystem: "com.writeassist", category: "WritingStatsStore")

struct WritingSession: Codable, Identifiable, Sendable {
    var id: UUID
    var date: Date
    var wordCount: Int
    var issuesByType: [String: Int]  // IssueType description -> count
    var correctionsApplied: Int
}

@MainActor
@Observable
final class WritingStatsStore: @unchecked Sendable {
    static let shared = WritingStatsStore()

    private(set) var sessions: [WritingSession] = []
    private let storageKey = "writingSessions"

    /// Current session tracking
    private(set) var currentSessionWordCount: Int = 0
    private(set) var currentSessionCorrections: Int = 0
    private var currentSessionIssues: [String: Int] = [:]
    private var sessionStartDate: Date = Date()

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([WritingSession].self, from: data) {
            sessions = decoded
        }
        logger.info("WritingStatsStore loaded \(self.sessions.count) sessions")
    }

    func recordWordCount(_ count: Int) {
        currentSessionWordCount = max(currentSessionWordCount, count)
    }

    func recordIssue(type: IssueType) {
        let key = type.categoryLabel
        currentSessionIssues[key, default: 0] += 1
    }

    func recordCorrection() {
        currentSessionCorrections += 1
    }

    func endSession() {
        guard currentSessionWordCount > 0 else { return }
        let session = WritingSession(
            id: UUID(),
            date: sessionStartDate,
            wordCount: currentSessionWordCount,
            issuesByType: currentSessionIssues,
            correctionsApplied: currentSessionCorrections
        )
        sessions.append(session)
        // Keep last 90 days of sessions
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        sessions = sessions.filter { $0.date >= cutoff }
        save()

        // Reset current session
        currentSessionWordCount = 0
        currentSessionCorrections = 0
        currentSessionIssues = [:]
        sessionStartDate = Date()

        logger.info("Session ended. Total sessions: \(self.sessions.count)")
    }

    // MARK: - Aggregation

    var totalWordsWritten: Int {
        sessions.reduce(0) { $0 + $1.wordCount }
    }

    var totalCorrections: Int {
        sessions.reduce(0) { $0 + $1.correctionsApplied }
    }

    var sessionsThisWeek: [WritingSession] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return sessions.filter { $0.date >= weekAgo }
    }

    var wordsThisWeek: Int {
        sessionsThisWeek.reduce(0) { $0 + $1.wordCount }
    }

    var topRecurringIssues: [(type: String, count: Int)] {
        var aggregate: [String: Int] = [:]
        for session in sessions {
            for (type, count) in session.issuesByType {
                aggregate[type, default: 0] += count
            }
        }
        return aggregate.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
