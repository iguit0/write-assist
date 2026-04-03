// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

/// Groups a flat `NLAnalysis` + `[WritingIssue]` result into a paragraph → sentence → issue hierarchy.
///
/// - All IDs use the range-based contract `"\(range.location):\(range.length)"`.
/// - Issue objects are never duplicated; only `issue.id` strings are stored on each node.
/// - Empty paragraphs (zero-length after enumeration) are skipped.
/// - Paragraphs with no matching sentences in `NLAnalysis` receive an empty `sentences` array.
enum ReviewGrouping {
    /// Groups a flat analysis result into paragraph → sentence → issue hierarchy.
    /// Call this after `DeterministicReviewEngine.analyze()` to fill in the paragraphs field.
    static func group(
        text: String,
        analysis: NLAnalysis,
        issues: [WritingIssue]
    ) -> [ReviewParagraphSnapshot] {
        // MARK: Step 1 — Split text into paragraphs

        var paragraphEntries: [(stringRange: Range<String.Index>, nsRange: NSRange)] = []

        text.enumerateSubstrings(
            in: text.startIndex...,
            options: [.byParagraphs, .substringNotRequired]
        ) { _, substringRange, _, _ in
            let nsRange = NSRange(substringRange, in: text)
            guard nsRange.length > 0 else { return }
            paragraphEntries.append((stringRange: substringRange, nsRange: nsRange))
        }

        // MARK: Step 2 + 3 + 4 — Build snapshots

        return paragraphEntries.map { paragraphStringRange, paragraphNSRange in
            let paragraphID = "\(paragraphNSRange.location):\(paragraphNSRange.length)"

            // --- Sentences that belong to this paragraph ---
            let sentences: [ReviewSentenceSnapshot] = analysis.sentenceRanges.compactMap { sentence, sentenceStringRange in
                let sentenceNSRange = NSRange(sentenceStringRange, in: text)
                guard overlaps(paragraphNSRange, sentenceNSRange) else { return nil }

                let sentenceID = "\(sentenceNSRange.location):\(sentenceNSRange.length)"
                let sentenceIssueIDs = issues
                    .filter { overlaps(sentenceNSRange, $0.range) }
                    .map(\.id)

                return ReviewSentenceSnapshot(
                    id: sentenceID,
                    range: sentenceNSRange,
                    text: sentence,
                    issueIDs: sentenceIssueIDs
                )
            }

            // --- Issues that belong to this paragraph ---
            let paragraphIssueIDs = issues
                .filter { overlaps(paragraphNSRange, $0.range) }
                .map(\.id)

            return ReviewParagraphSnapshot(
                id: paragraphID,
                range: paragraphNSRange,
                text: String(text[paragraphStringRange]),
                sentences: sentences,
                issueIDs: paragraphIssueIDs
            )
        }
    }

    // MARK: - Helpers

    private static func overlaps(_ a: NSRange, _ b: NSRange) -> Bool {
        NSIntersectionRange(a, b).length > 0
    }
}
