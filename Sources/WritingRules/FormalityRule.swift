// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

struct FormalityRule: WritingRule {
    let ruleID = "formality"
    let issueType = IssueType.style

    // Codable mirrors for JSON decoding (#022)
    private struct JSONFormalPair: Decodable {
        let formal: String
        let informal: String
    }
    private struct JSONInformalPair: Decodable {
        let informal: String
        let formal: String
    }
    private struct JSONContraction: Decodable {
        let contraction: String
        let expansion: String
    }
    private struct JSONRoot: Decodable {
        let formalToInformal: [JSONFormalPair]
        let informalToFormal: [JSONInformalPair]
        let contractions: [JSONContraction]
    }

    private static let jsonRoot: JSONRoot? = {
        guard let url = Bundle.module.url(forResource: "formality-words", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(JSONRoot.self, from: data)
        else { return nil }
        return root
    }()

    // Load word lists from Bundle.module JSON; fall back to empty (non-fatal).
    private static let formalToInformal: [(formal: String, informal: String)] = {
        jsonRoot?.formalToInformal.map { (formal: $0.formal, informal: $0.informal) } ?? []
    }()

    private static let informalToFormal: [(informal: String, formal: String)] = {
        jsonRoot?.informalToFormal.map { (informal: $0.informal, formal: $0.formal) } ?? []
    }()

    private static let contractions: [(contraction: String, expansion: String)] = {
        jsonRoot?.contractions.map { (contraction: $0.contraction, expansion: $0.expansion) } ?? []
    }()

    func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
        // Formality level is read from the snapshot stored in NLAnalysis context.
        // This avoids accessing @MainActor PreferencesManager from a nonisolated context.
        let formality = analysis.formalityLevel
        guard formality != .neutral else { return [] }

        let lower = text.lowercased()
        let nsText = text as NSString
        var issues: [WritingIssue] = []

        if formality == .informal {
            // Flag overly formal language
            for (formal, informal) in Self.formalToInformal {
                findAndReport(
                    phrase: formal, in: lower, nsText: nsText, fullText: text,
                    message: "Too formal for informal writing — try \"\(informal)\"",
                    suggestion: informal, issues: &issues
                )
            }
        } else if formality == .formal {
            // Flag informal language
            for (informal, formal) in Self.informalToFormal {
                findAndReport(
                    phrase: informal, in: lower, nsText: nsText, fullText: text,
                    message: formal.isEmpty
                        ? "Informal language — consider removing"
                        : "Informal language — try \"\(formal)\"",
                    suggestion: formal, issues: &issues
                )
            }
            // Flag contractions
            for (contraction, expansion) in Self.contractions {
                findAndReport(
                    phrase: contraction, in: lower, nsText: nsText, fullText: text,
                    message: "Avoid contractions in formal writing — use \"\(expansion)\"",
                    suggestion: expansion, issues: &issues
                )
            }
        }

        return issues
    }

    private func findAndReport(
        phrase: String,
        in lower: String,
        nsText: NSString,
        fullText: String,
        message: String,
        suggestion: String,
        issues: inout [WritingIssue]
    ) {
        var searchStart = lower.startIndex
        while let range = lower.range(of: phrase, range: searchStart..<lower.endIndex) {
            let nsRange = NSRange(range, in: fullText)
            guard nsRange.location + nsRange.length <= nsText.length else { break }

            // Word boundary check — avoids matching inside larger words
            let before = range.lowerBound > lower.startIndex
                ? lower[lower.index(before: range.lowerBound)]
                : nil
            let after = range.upperBound < lower.endIndex
                ? lower[range.upperBound]
                : nil
            let isWordBounded = (before == nil || !before!.isLetter)
                && (after == nil || !after!.isLetter)

            if isWordBounded {
                let word = nsText.substring(with: nsRange)
                issues.append(WritingIssue(
                    type: .style,
                    ruleID: ruleID,
                    range: nsRange,
                    word: word,
                    message: message,
                    suggestions: suggestion.isEmpty ? [] : [suggestion]
                ))
            }

            searchStart = range.upperBound
        }
    }
}
