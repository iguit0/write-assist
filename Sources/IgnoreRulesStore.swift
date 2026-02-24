// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import os

private let logger = Logger(subsystem: "com.writeassist", category: "IgnoreRulesStore")

struct IgnoreRule: Codable, Hashable {
    let word: String
    let ruleID: String?  // nil means ignore for all rules
}

@MainActor
@Observable
final class IgnoreRulesStore: @unchecked Sendable {
    static let shared = IgnoreRulesStore()

    private(set) var rules: Set<IgnoreRule> = []
    private let storageKey = "ignoreRules"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(Set<IgnoreRule>.self, from: data) {
            rules = decoded
        }
        logger.info("IgnoreRulesStore loaded \(self.rules.count) rules")
    }

    func addRule(word: String, ruleID: String? = nil) {
        let rule = IgnoreRule(word: word, ruleID: ruleID)
        guard !rules.contains(rule) else { return }
        rules.insert(rule)
        save()
        logger.info("Added ignore rule: '\(word)' for rule: \(ruleID ?? "all")")
    }

    func removeRule(_ rule: IgnoreRule) {
        rules.remove(rule)
        save()
        logger.info("Removed ignore rule: '\(rule.word)'")
    }

    func isIgnored(word: String, ruleID: String) -> Bool {
        rules.contains(IgnoreRule(word: word, ruleID: ruleID))
            || rules.contains(IgnoreRule(word: word, ruleID: nil))
    }

    func clearAll() {
        rules.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
