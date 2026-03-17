// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

@preconcurrency import AppKit
import os

private let logger = Logger(subsystem: "com.writeassist", category: "SpellCheckService")

enum SpellCheckService {
    private struct TextCheckingResultsBox: @unchecked Sendable {
        let results: [NSTextCheckingResult]
    }

    /// Hard timeout for a spell-check pass. Protects against the XPC service
    /// stalling (proven to happen via production logs).
    private static let timeout: Duration = .milliseconds(800)

    /// Async spell + grammar check.
    ///
    /// Uses `requestChecking` (async callback API) to avoid blocking the main
    /// thread while the XPC spell-check service works. The callback is created
    /// outside `@MainActor` isolation so it can safely fire on a background
    /// thread without triggering main-queue assertions.
    ///
    /// Falls back to empty results if the check times out.
    static func check(text: String) async -> [WritingIssue] {
        guard !(text as NSString).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let startTime = ContinuousClock.now
        logger.debug("check: starting (text length: \(text.count))")

        // Race the check against a timeout
        let result: [WritingIssue]? = await withTaskGroup(of: [WritingIssue]?.self) { group in
            group.addTask {
                await Self.performCheck(text: text)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil // timeout sentinel
            }
            // First to finish wins
            if let first = await group.next() {
                group.cancelAll()
                return first
            }
            return nil
        }

        let elapsed = ContinuousClock.now - startTime
        if let result {
            logger.debug("check: complete in \(elapsed) — \(result.count) issues found")
            return result
        } else {
            logger.warning("check: TIMED OUT after \(elapsed) — returning empty")
            return []
        }
    }

    // MARK: - Synchronous Spell Check

    /// Runs spell + grammar check via `requestChecking` (non-blocking).
    ///
    /// NSSpellChecker must stay on the main thread, but the async callback API
    /// lets us yield while the XPC service works instead of blocking the run loop.
    private static func performCheck(text: String) async -> [WritingIssue] {
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let results = await requestCheckingResults(text: text, range: range)
        guard !Task.isCancelled else { return [] }
        return await processResults(results, text: text)
    }

    private nonisolated static func requestCheckingResults(
        text: String,
        range: NSRange
    ) async -> [NSTextCheckingResult] {
        await withCheckedContinuation { continuation in
            let handler: @Sendable (Int, [NSTextCheckingResult], NSOrthography, Int) -> Void = {
                _, results, _, _ in
                continuation.resume(returning: TextCheckingResultsBox(results: results))
            }

            Task { @MainActor in
                let checker = NSSpellChecker.shared
                _ = checker.requestChecking(
                    of: text,
                    range: range,
                    types: NSTextCheckingResult.CheckingType.spelling.rawValue
                         | NSTextCheckingResult.CheckingType.grammar.rawValue,
                    options: nil,
                    inSpellDocumentWithTag: 0,
                    completionHandler: handler
                )
            }
        }.results
    }

    // MARK: - Result Processing

    /// Converts `NSTextCheckingResult` array into `[WritingIssue]`.
    /// Fetches spelling suggestions via `guesses(forWordRange:...)`.
    /// Must be called on the main thread.
    @MainActor
    private static func processResults(
        _ results: [NSTextCheckingResult],
        text: String
    ) -> [WritingIssue] {
        let checker = NSSpellChecker.shared
        let nsString = text as NSString
        var issues: [WritingIssue] = []

        for result in results {
            // Guard against stale ranges
            guard result.range.location + result.range.length <= nsString.length else {
                continue
            }

            switch result.resultType {
            case .spelling:
                let word = nsString.substring(with: result.range)
                let guesses = checker.guesses(
                    forWordRange: result.range,
                    in: text,
                    language: checker.language(),
                    inSpellDocumentWithTag: 0
                ) ?? []
                issues.append(WritingIssue(
                    type: .spelling,
                    ruleID: "spelling",
                    range: result.range,
                    word: word,
                    message: "Misspelled word",
                    suggestions: guesses
                ))

            case .grammar:
                if let details = result.grammarDetails {
                    for detail in details {
                        guard let rangeValue = detail["NSGrammarRange"] as? NSValue else {
                            continue
                        }
                        let detailRange = rangeValue.rangeValue
                        guard detailRange.location + detailRange.length <= nsString.length else {
                            continue
                        }
                        let word = nsString.substring(with: detailRange)
                        let corrections = detail["NSGrammarCorrections"] as? [String] ?? []
                        let description = detail["NSGrammarUserDescription"] as? String
                            ?? "Grammar issue"

                        // Skip if overlapping with a spelling issue
                        let overlapsSpelling = issues.contains { existing in
                            existing.type == .spelling
                                && NSIntersectionRange(existing.range, detailRange).length > 0
                        }

                        if !overlapsSpelling {
                            issues.append(WritingIssue(
                                type: .grammar,
                                ruleID: "grammar",
                                range: detailRange,
                                word: word,
                                message: description,
                                suggestions: corrections
                            ))
                        }
                    }
                }

            default:
                break
            }
        }

        return issues
    }
}
