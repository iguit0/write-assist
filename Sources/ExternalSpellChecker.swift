// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

@preconcurrency import AppKit
import os

private let logger = Logger(subsystem: "com.writeassist", category: "ExternalSpellChecker")

/// Detects spelling errors in real-time as the user types in external apps,
/// then fires `onIssueDetected` so the caller can show the ErrorHUDPanel.
///
/// **Grammarly-style flow:**
/// 1. `GlobalInputMonitor` calls `scheduleCheck()` whenever a word-boundary key
///    (space, punctuation, Return) follows a word character.
/// 2. `scheduleCheck()` cancels any earlier pending check and starts an 800 ms
///    debounce Task — the check only runs after the user pauses typing.
/// 3. After the debounce: read the word immediately before the text cursor via
///    Accessibility API, spell-check it with NSSpellChecker (synchronous, offline),
///    fire `onIssueDetected` if misspelled.
///
/// **What makes this safe:**
/// - `onKeystroke` (in StatusBarController) calls `cancel()` on every keystroke,
///   resetting the debounce clock. Only a real pause triggers a check.
/// - A PID guard skips WriteAssist's own text views (handled by DocumentViewModel).
/// - Only collapsed cursors (no active text selection) are eligible.
/// - Words shorter than 3 characters and non-letter strings are skipped.
/// - Words in PersonalDictionary are silently skipped.
@MainActor
final class ExternalSpellChecker {

    /// Fires on `@MainActor` when a misspelled word is found.
    /// Parameters: (WritingIssue with suggestions, screen bounds of the word in AX coords)
    var onIssueDetected: ((WritingIssue, CGRect) -> Void)?

    private var debounceTask: Task<Void, Never>?

    // Grammarly checks ~500–800 ms after the user stops typing a word.
    private let debounceDelay: Duration = .milliseconds(800)

    // MARK: - Public API

    /// Called by GlobalInputMonitor when a word-boundary key is pressed.
    /// Cancels any earlier scheduled check and starts a fresh 800 ms debounce.
    func scheduleCheck() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: debounceDelay)
            } catch {
                return // cancelled — user kept typing
            }
            await self.runCheck()
        }
    }

    /// Cancels any pending debounce. Call on every raw keystroke so the clock resets.
    func cancel() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    // MARK: - Private

    private func runCheck() async {
        guard let (word, range, bounds) = await Self.readWordBeforeCursorAsync() else {
            logger.debug("runCheck: no word found before cursor")
            return
        }

        // Skip words in personal dictionary
        guard !PersonalDictionary.shared.containsWord(word) else {
            logger.debug("runCheck: '\(word, privacy: .sensitive)' is in personal dictionary — skipping")
            return
        }

        // Spell-check (synchronous NSSpellChecker — typically < 5 ms)
        guard let suggestions = Self.spellCheckWord(word) else {
            logger.debug("runCheck: '\(word, privacy: .sensitive)' is correctly spelled")
            return
        }

        logger.info("runCheck: '\(word, privacy: .sensitive)' is misspelled → \(suggestions.count) suggestions")

        let issue = WritingIssue(
            type: .spelling,
            range: range,
            word: word,
            message: "Misspelled word",
            suggestions: suggestions
        )
        onIssueDetected?(issue, bounds)
    }

    // MARK: - NSSpellChecker (synchronous)

    /// Returns correction suggestions if `word` is misspelled, `nil` if correctly spelled.
    /// Skips strings that contain no letters (numbers, URLs, code tokens, etc.).
    private static func spellCheckWord(_ word: String) -> [String]? {
        // Must contain at least one letter; skip pure-numeric or symbol strings.
        guard word.contains(where: { $0.isLetter }) else { return nil }

        let checker = NSSpellChecker.shared
        let nsWord = word as NSString

        // `checkSpelling` returns a range of length 0 when the word is correctly spelled.
        let misspelledRange = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: nil,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        guard misspelledRange.length > 0 else { return nil }

        let guesses = checker.guesses(
            forWordRange: NSRange(location: 0, length: nsWord.length),
            in: word,
            language: checker.language(),
            inSpellDocumentWithTag: 0
        ) ?? []

        // Cap at 4 suggestions to match ErrorHUDPanel's display limit.
        return Array(guesses.prefix(4))
    }

    // MARK: - AX Word Reading

    private static func readWordBeforeCursorAsync() async -> (String, NSRange, CGRect)? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.readWordBeforeCursor())
            }
        }
    }

    /// Reads the word immediately before the text cursor in the focused UI element.
    /// Returns `nil` if the element is part of WriteAssist itself, if there is an
    /// active text selection, if the AX read fails, or if no eligible word is found.
    private nonisolated static func readWordBeforeCursor() -> (String, NSRange, CGRect)? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }

        let element = focusedRef as! AXUIElement // safe: type ID verified above

        // Skip WriteAssist's own text fields — DocumentViewModel handles those.
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if pid == ProcessInfo.processInfo.processIdentifier { return nil }

        // Get the cursor position (kAXSelectedTextRange → CFRange).
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeRef else { return nil }

        var cfRange = CFRange(location: 0, length: 0)
        // Safe force-cast: kAXSelectedTextRangeAttribute always returns AXValue.
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &cfRange) else { return nil }

        // Only check when there is NO active selection (collapsed cursor).
        // If the user has text selected, spell-checking the word before the cursor
        // would be confusing and could conflict with SelectionSuggestionPanel.
        guard cfRange.length == 0 else { return nil }
        let cursorUTF16 = cfRange.location

        // Read the full text of the element.
        var textRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &textRef
        ) == .success,
              let textRef,
              let fullText = textRef as? String,
              !fullText.isEmpty
        else { return nil }

        // Extract the word that ends just before the cursor.
        guard let (word, wordRange) = extractWordBefore(cursorUTF16: cursorUTF16, in: fullText)
        else { return nil }

        // Query AX for the on-screen bounds of the word (for HUD positioning).
        var cfWordRange = CFRange(location: wordRange.location, length: wordRange.length)
        var bounds = CGRect.zero
        if let axWordRange = AXValueCreate(.cfRange, &cfWordRange) {
            var boundsRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                axWordRange,
                &boundsRef
            ) == .success, let boundsRef {
                // Safe force-cast: kAXBoundsForRangeParameterizedAttribute returns AXValue.
                AXValueGetValue(boundsRef as! AXValue, .cgRect, &bounds)
            }
        }

        return (word, wordRange, bounds)
    }

    /// Scans backward from `cursorUTF16` (a UTF-16 offset) to find the last
    /// complete word in `text`. Handles apostrophes (can't) and hyphens (well-known).
    ///
    /// Returns `nil` if the word is fewer than 3 characters.
    private nonisolated static func extractWordBefore(
        cursorUTF16: Int,
        in text: String
    ) -> (String, NSRange)? {
        let nsText = text as NSString
        guard cursorUTF16 > 0, cursorUTF16 <= nsText.length else { return nil }

        var pos = cursorUTF16 - 1

        // Step 1: Skip the boundary character(s) trailing the cursor
        //         (the space or punctuation the user just typed).
        while pos >= 0, !isWordChar(nsText.character(at: pos)) {
            pos -= 1
        }
        guard pos >= 0 else { return nil }
        let wordEnd = pos + 1 // exclusive, in UTF-16 units

        // Step 2: Scan backward to the start of the word.
        var wordStart = pos
        while wordStart > 0, isWordChar(nsText.character(at: wordStart - 1)) {
            wordStart -= 1
        }

        let wordRange = NSRange(location: wordStart, length: wordEnd - wordStart)
        let word = nsText.substring(with: wordRange)

        // Require at least 3 characters to reduce false positives on short tokens.
        guard word.count >= 3 else { return nil }

        return (word, wordRange)
    }

    /// A character is a "word character" if it can appear inside a word:
    /// letters, digits, apostrophe/right-single-quote (contractions), hyphen.
    private nonisolated static func isWordChar(_ c: unichar) -> Bool {
        // Unicode.Scalar(unichar) returns nil for surrogate halves — treat those as non-word.
        guard let scalar = Unicode.Scalar(c) else { return false }
        let char = Character(scalar)
        if char.isLetter || char.isNumber { return true }
        // U+0027 APOSTROPHE, U+2019 RIGHT SINGLE QUOTATION MARK (curly apostrophe)
        if c == 0x0027 || c == 0x2019 { return true }
        // U+002D HYPHEN-MINUS
        if c == 0x002D { return true }
        return false
    }
}
