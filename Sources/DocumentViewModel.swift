// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

@preconcurrency import AppKit
import CoreGraphics
import os

private let logger = Logger(subsystem: "com.writeassist", category: "DocumentViewModel")

/// All mutable state is accessed exclusively on @MainActor.
/// `@unchecked Sendable` is retained because `@Observable` classes used across
/// closure boundaries (e.g., `onNewIssuesReadyForHUD` callbacks) may require
/// `Sendable` conformance in Swift 6 strict concurrency mode.
@MainActor
@Observable
final class DocumentViewModel: @unchecked Sendable {
    var text: String = ""
    var issues: [WritingIssue] = []
    var ignoredRanges: Set<String> = []

    /// IDs of issues that arrived since the popover was last opened.
    /// Used to show "new" indicators on issue cards.
    var unseenIssueIDs: Set<UUID> = []

    /// Called by StatusBarController when new issues are ready to be shown in the HUD.
    /// Receives the array of issues that haven't been shown to the user yet in this typing session.
    var onNewIssuesReadyForHUD: (([WritingIssue]) -> Void)?

    /// Keys of issues whose HUD has already been shown in the current typing session.
    /// Cleared on every textDidChange from USER typing so the HUD can re-appear
    /// after the user keeps typing. NOT cleared during programmatic buffer updates
    /// (e.g., after applying a correction) to prevent re-triggering HUDs.
    private var hudShownKeys: Set<String> = []

    /// Keys of issues that were just corrected. Suppresses re-showing the HUD for
    /// a word that was already corrected (while the buffer may still contain it).
    /// Entries are pruned automatically when the issue disappears from detection.
    private var recentlyCorrectedKeys: Set<String> = []

    /// True while a correction is being applied (AX injection in flight).
    /// Suppresses HUD display to prevent competing AX calls and rapid HUD cycling.
    private(set) var isCorrectionInFlight = false

    /// Timestamp of the last correction. Used to enforce a cooldown period
    /// before allowing new HUD popups (prevents rapid show/dismiss cycles).
    private var lastCorrectionTime: ContinuousClock.Instant?

    /// Minimum time after a correction before a new HUD can appear.
    private let hudCooldownAfterCorrection: Duration = .seconds(1.5)

    /// Whether the current textDidChange call originates from a programmatic
    /// buffer update (correction) rather than user typing.
    private var isProgrammaticBufferUpdate = false

    /// Weak reference to the input monitor so we can update the buffer after correction.
    weak var inputMonitor: GlobalInputMonitor?

    /// Call this when the popover opens to mark all current issues as seen.
    func markAllSeen() {
        unseenIssueIDs.removeAll()
    }

    var wordCount: Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    var characterCount: Int {
        text.count
    }

    /// Writing score: 100 minus penalties per active issue (spelling −5, grammar −3), min 0.
    var writingScore: Int {
        guard !text.isEmpty else { return 100 }
        let active = issues.filter { !$0.isIgnored }
        let penalty = active.reduce(0) { $0 + ($1.type == .spelling ? 5 : 3) }
        return max(0, 100 - penalty)
    }

    var spellingCount: Int { issues.filter { $0.type == .spelling && !$0.isIgnored }.count }
    var grammarCount: Int { issues.filter { $0.type == .grammar && !$0.isIgnored }.count }

    private var checkTask: Task<Void, Never>?

    func textDidChange(_ newText: String) {
        text = newText
        ignoredRanges = []
        // Only reset HUD shown keys when the user is TYPING (not after a
        // programmatic correction). Clearing hudShownKeys after a correction
        // was causing ALL remaining issues to re-trigger the HUD, leading to
        // rapid show/dismiss cycles and competing AX calls that deadlocked.
        if !isProgrammaticBufferUpdate {
            logger.debug("textDidChange: user typing — clearing hudShownKeys")
            hudShownKeys = []
        } else {
            logger.debug("textDidChange: programmatic update — preserving hudShownKeys")
        }
        scheduleCheck()
    }

    func scheduleCheck() {
        checkTask?.cancel()
        checkTask = Task { @MainActor in
            // 0.2s debounce — fast enough to feel responsive, long enough to avoid
            // checking on every character
            try? await Task.sleep(for: .seconds(0.2))
            guard !Task.isCancelled else { return }
            await runCheck()
        }
    }

    func runCheck() async {
        logger.debug("runCheck: starting spell check (text length: \(self.text.count))")
        let detected = await SpellCheckService.check(text: text)
        guard !Task.isCancelled else {
            logger.debug("runCheck: cancelled after spell check returned")
            return
        }
        logger.debug("runCheck: spell check complete — \(detected.count) raw issues")
        let newIssues = detected.filter { !ignoredRanges.contains(ignoredKey(for: $0)) }

        // Track which issues are genuinely new (not already in the list by word+range)
        // Used for the badge "unseen" indicator in the sidebar
        let existingKeys = Set(issues.map { ignoredKey(for: $0) })
        let brandNew = newIssues.filter { !existingKeys.contains(ignoredKey(for: $0)) }
        unseenIssueIDs.formUnion(brandNew.map(\.id))

        issues = newIssues

        // Prune recentlyCorrectedKeys: once an issue disappears from detection (i.e.,
        // the correction was actually applied in the external app), we can forget it.
        // Keep entries only for issues that are STILL detected (buffer desync case).
        let currentKeys = Set(newIssues.map { ignoredKey(for: $0) })
        recentlyCorrectedKeys = recentlyCorrectedKeys.filter { currentKeys.contains($0) }

        // ── HUD gating ──────────────────────────────────────────────────────────
        // Suppress HUD when a correction is in flight (AX calls still active)
        // or within the cooldown period after the last correction.
        if isCorrectionInFlight {
            logger.debug("runCheck: skipping HUD — correction in flight")
            return
        }
        if let lastTime = lastCorrectionTime,
           ContinuousClock.now - lastTime < hudCooldownAfterCorrection {
            logger.debug("runCheck: skipping HUD — within cooldown period")
            return
        }

        // Determine which issues haven't had their HUD shown yet in this typing session.
        // Also skip issues that were just corrected (even if buffer still detects them).
        let pendingHUD = newIssues.filter {
            !hudShownKeys.contains(ignoredKey(for: $0)) &&
            !recentlyCorrectedKeys.contains(ignoredKey(for: $0))
        }
        if !pendingHUD.isEmpty {
            logger.debug("runCheck: \(pendingHUD.count) issues pending HUD display")
            // Mark them so we don't double-show in the same session
            for issue in pendingHUD {
                hudShownKeys.insert(ignoredKey(for: issue))
            }
            onNewIssuesReadyForHUD?(pendingHUD)
        }
    }

    /// Applies the correction in-place in the focused application.
    ///
    /// This function performs all UI state updates synchronously on @MainActor,
    /// then fires off AX injection on a background thread with a hard 0.8s timeout.
    /// This prevents any AX API call from ever blocking the main thread — which was
    /// the root cause of the permanent freeze after the first correction.
    ///
    /// Strategy:
    ///  1. Background Task: AX-based in-place word replacement (select word → replace).
    ///  2. If AX times out or fails: clipboard + simulated Cmd+V (session-level tap).
    ///  3. Ultimate fallback: clipboard only (correction is always on the pasteboard).
    func applyCorrection(_ issue: WritingIssue, correction: String) {
        logger.info("applyCorrection: '\(issue.word)' → '\(correction)' [START]")

        // ── Phase 1: fast @MainActor state updates ────────────────────────────
        isCorrectionInFlight = true
        lastCorrectionTime = .now

        // Always write to clipboard as a safety net / last-resort fallback
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(correction, forType: .string)
        logger.debug("applyCorrection: clipboard set")

        // Remove issue from local list immediately so sidebar UI updates now
        issues.removeAll { $0.id == issue.id }
        logger.debug("applyCorrection: issue removed from list (\(self.issues.count) remaining)")

        // Mark as recently corrected so runCheck() won't re-trigger the HUD
        // for this word while the buffer may still contain it.
        recentlyCorrectedKeys.insert(ignoredKey(for: issue))

        // Update the input monitor's buffer to reflect the corrected text so
        // the next spell-check doesn't re-detect the same error.
        // Set the programmatic flag so textDidChange preserves hudShownKeys.
        isProgrammaticBufferUpdate = true
        inputMonitor?.replaceInBuffer(old: issue.word, new: correction)
        isProgrammaticBufferUpdate = false
        logger.debug("applyCorrection: buffer updated, programmatic flag reset")

        // ── Phase 2: AX injection — background thread with 1-second timeout ───
        //
        // CRITICAL: We must NEVER block @MainActor with AX C calls.
        // Strategy: fire background GCD task, return immediately.
        // If AX succeeds → word replaced in-place in target app, timed fallback cancelled.
        // If AX fails   → clipboard paste (already set in Phase 1).
        // If AX hangs   → 1-second deadline fires the paste fallback so the user
        //                  doesn't wait indefinitely if AX is stuck.
        let word = issue.word
        let fallbackItem = DispatchWorkItem { [weak self] in
            logger.warning("applyCorrection: AX timed out — firing paste fallback")
            Self.simulatePasteStatic()
            Task { @MainActor in
                self?.isCorrectionInFlight = false
                logger.debug("applyCorrection: correctionInFlight cleared (timeout path)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: fallbackItem)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            logger.debug("applyCorrection: AX injection starting on background thread")
            let axSucceeded = Self.injectCorrectionViaAXBackground(
                word: word, correction: correction
            )
            logger.info("applyCorrection: AX injection result = \(axSucceeded)")
            // Cancel the timed fallback — we'll handle it ourselves
            fallbackItem.cancel()
            if !axSucceeded {
                logger.warning("applyCorrection: AX failed — firing paste fallback")
                DispatchQueue.main.async { Self.simulatePasteStatic() }
            }
            Task { @MainActor in
                self?.isCorrectionInFlight = false
                logger.debug("applyCorrection: correctionInFlight cleared (normal path)")
            }
        }
        logger.debug("applyCorrection: Phase 1 complete, background AX dispatched [END sync]")
    }

    /// AX-based word replacement — runs on a background thread (nonisolated).
    /// Returns true if the replacement was successfully applied.
    ///
    /// Marked `nonisolated` and `static` so it can be called from a detached Task
    /// without capturing `self` across actor boundaries.
    private nonisolated static func injectCorrectionViaAXBackground(
        word: String,
        correction: String
    ) -> Bool {
        logger.debug("AX-bg: getting focused element")
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success, let focusedValue else {
            logger.warning("AX-bg: failed to get focused element")
            return false
        }
        // CF types cannot be checked with `as?` — validate via CFGetTypeID before casting.
        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            logger.warning("AX-bg: focused value is not an AXUIElement")
            return false
        }
        let element = focusedValue as! AXUIElement // safe: type ID verified above

        // Read the current text of the focused element
        logger.debug("AX-bg: reading text value")
        var textValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &textValue
        ) == .success,
        let textValue,
        let fullText = textValue as? String else {
            logger.warning("AX-bg: failed to read text value from focused element")
            return false
        }

        // Find the last occurrence of the misspelled word in the element's text
        // (using the last occurrence because the buffer tracks the tail of the document)
        guard let wordRange = fullText.range(of: word, options: .backwards) else {
            logger.warning("AX-bg: word '\(word)' not found in element text")
            return false
        }
        let nsRange = NSRange(wordRange, in: fullText)

        // Build CFRange for the AX API
        var cfRange = CFRange(location: nsRange.location, length: nsRange.length)
        guard let axRange = AXValueCreate(.cfRange, &cfRange) else { return false }

        // Select the misspelled word
        logger.debug("AX-bg: setting selected text range")
        let setRangeResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            axRange
        )
        guard setRangeResult == .success else {
            logger.warning("AX-bg: failed to set selected text range")
            return false
        }

        // Replace selected text with the correction
        logger.debug("AX-bg: setting selected text to '\(correction)'")
        let setTextResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            correction as CFString
        )
        logger.debug("AX-bg: set text result = \(setTextResult == .success ? "success" : "failed")")
        return setTextResult == .success
    }

    /// Posts a synthetic Cmd+V key event to paste clipboard content into the
    /// currently focused application. Used as a fallback when AX injection fails or times out.
    /// Uses .cgAnnotatedSessionEventTap (session-level) to avoid HID-level permission issues.
    /// `static` so it can be called from a detached Task without capturing `self`.
    private static func simulatePasteStatic() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Virtual key code 9 = V on US keyboard layout
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags   = .maskCommand
        vDown?.post(tap: .cgAnnotatedSessionEventTap)
        vUp?.post(tap: .cgAnnotatedSessionEventTap)
    }

    func ignoreIssue(_ issue: WritingIssue) {
        ignoredRanges.insert(ignoredKey(for: issue))
        issues.removeAll { $0.id == issue.id }
    }

    private func ignoredKey(for issue: WritingIssue) -> String {
        "\(issue.word):\(issue.range.location)"
    }
}
