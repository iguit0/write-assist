// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import os

private let logger = Logger(subsystem: "com.writeassist", category: "SnippetsManager")

struct Snippet: Identifiable, Codable, Sendable {
    var id: UUID
    var trigger: String      // e.g., "/sig"
    var name: String         // Human-readable label
    var expansion: String    // The expanded text
}

@MainActor
@Observable
final class SnippetsManager: @unchecked Sendable {
    static let shared = SnippetsManager()

    private(set) var snippets: [Snippet] = []
    private let storageKey = "snippets"

    /// The trigger character that begins a snippet expansion (default: "/").
    var triggerPrefix: String {
        didSet { UserDefaults.standard.set(triggerPrefix, forKey: "snippetTriggerPrefix") }
    }

    private init() {
        triggerPrefix = UserDefaults.standard.string(forKey: "snippetTriggerPrefix") ?? "/"
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Snippet].self, from: data) {
            snippets = decoded
        } else {
            // Default snippets
            snippets = [
                Snippet(id: UUID(), trigger: "/sig", name: "Email Signature",
                        expansion: "Best regards,\n"),
                Snippet(id: UUID(), trigger: "/ty", name: "Thank You",
                        expansion: "Thank you for your time and consideration."),
                Snippet(id: UUID(), trigger: "/greet", name: "Greeting",
                        expansion: "I hope this message finds you well."),
            ]
            save()
        }
        logger.info("SnippetsManager loaded \(self.snippets.count) snippets")
    }

    func addSnippet(trigger: String, name: String, expansion: String) {
        let snippet = Snippet(id: UUID(), trigger: trigger, name: name, expansion: expansion)
        snippets.append(snippet)
        save()
        logger.info("Added snippet: '\(trigger)' -> '\(name)'")
    }

    func removeSnippet(id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    func updateSnippet(_ snippet: Snippet) {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[idx] = snippet
            save()
        }
    }

    func matchingSnippet(for text: String) -> Snippet? {
        let lower = text.lowercased()
        return snippets.first { lower.hasSuffix($0.trigger.lowercased()) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snippets) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
