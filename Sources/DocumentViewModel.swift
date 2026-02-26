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

    /// Cached NL analysis result, updated on each check cycle.
    private(set) var cachedAnalysis: NLAnalysis?

    /// Active category filter for the issue list. Nil means show all.
    var selectedCategory: IssueCategory?

    /// Detected tone from the latest NL analysis.
    var detectedTone: DetectedTone { cachedAnalysis?.detectedTone ?? .neutral }

    /// Call this when the popover opens to mark all current issues as seen.
    func markAllSeen() {
        unseenIssueIDs.removeAll()
    }

    // MARK: - Basic Stats

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

    // MARK: - Metrics

    var sentenceCount: Int {
        cachedAnalysis?.sentenceCount ?? max(1, text.components(separatedBy: .init(charactersIn: ".!?")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count)
    }

    var averageSentenceLength: Double {
        cachedAnalysis?.averageSentenceLength ?? (wordCount > 0 ? Double(wordCount) / Double(sentenceCount) : 0)
    }

    var paragraphCount: Int {
        guard !text.isEmpty else { return 0 }
        return text.components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    var vocabularyDiversity: Double {
        cachedAnalysis?.vocabularyDiversity ?? 0
    }

    var averageWordLength: Double {
        cachedAnalysis?.averageWordLength ?? 0
    }

    /// Flesch-Kincaid readability score.
    /// 206.835 - 1.015*(words/sentences) - 84.6*(syllables/words)
    var readabilityScore: Double {
        let wc = Double(wordCount)
        let sc = Double(sentenceCount)
        let syllables = Double(cachedAnalysis?.syllableCount ?? wordCount)
        guard wc > 0, sc > 0 else { return 100 }
        let score = 206.835 - 1.015 * (wc / sc) - 84.6 * (syllables / wc)
        return max(0, min(100, score))
    }

    /// Estimated reading time in minutes (250 wpm).
    var readingTime: Double {
        Double(wordCount) / 250.0
    }

    /// Estimated speaking time in minutes (150 wpm).
    var speakingTime: Double {
        Double(wordCount) / 150.0
    }

    // MARK: - Writing Score

    /// Multi-dimensional writing score combining correctness, clarity, engagement, and delivery.
    // MARK: - Issue Counts

    var spellingCount: Int { issues.filter { $0.type == .spelling && !$0.isIgnored }.count }
    var grammarCount: Int { issues.filter { $0.type == .grammar && !$0.isIgnored }.count }
    var clarityCount: Int { issues.filter { $0.type.category == .clarity && !$0.isIgnored }.count }
    var styleCount: Int { issues.filter { $0.type.category == .delivery && !$0.isIgnored }.count }
    var engagementCount: Int { issues.filter { $0.type.category == .engagement && !$0.isIgnored }.count }

    var totalActiveIssueCount: Int { issues.filter { !$0.isIgnored }.count }

    /// Issues filtered by the currently selected category (nil = all).
    var filteredIssues: [WritingIssue] {
        let active = issues.filter { !$0.isIgnored }
        guard let category = selectedCategory else { return active }
        return active.filter { $0.type.category == category }
    }

    // MARK: - Check Scheduling

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

    /// AI-first spell check with `SpellCheckService` (NSSpellChecker) fallback.
    /// Uses a 3 s timeout — must exceed `CloudAIService.minRequestInterval` (1 s) plus
    /// typical network latency so the rate-limiting sleep never races the sentinel.
    /// Silent fallback on any AI error so the user always gets spell results.
    private func resolveSpellIssues(text: String) async -> [WritingIssue] {
        let ai = CloudAIService.shared
        guard ai.isConfigured else {
            logger.debug("resolveSpellIssues: AI not configured — using SpellCheckService")
            return await SpellCheckService.check(text: text)
        }

        // Skip AI for very short text — not worth the latency/cost.
        guard text.count > 3 else {
            logger.debug("resolveSpellIssues: text too short (\(text.count) chars) — using SpellCheckService")
            return await SpellCheckService.check(text: text)
        }

        logger.debug("resolveSpellIssues: AI configured — attempting AI spell check")

        let aiResult: [WritingIssue]? = await withTaskGroup(of: [WritingIssue]?.self) { group in
            group.addTask {
                do {
                    return try await ai.spellCheck(text: text)
                } catch is CancellationError {
                    // Swift structured concurrency cancellation — superseded by a newer check.
                    return nil
                } catch let urlError as URLError where urlError.code == .cancelled {
                    // URLSession task was cancelled because the parent task was cancelled.
                    return nil
                } catch {
                    logger.warning("resolveSpellIssues: AI error — \(error.localizedDescription)")
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return nil // timeout sentinel
            }
            // Return the first result (AI response or timeout nil)
            let first = await group.next()
            group.cancelAll()
            return first ?? nil
        }

        if let result = aiResult {
            logger.debug("resolveSpellIssues: AI returned \(result.count) spelling issues")
            return result
        }

        // Don't fall through to SpellCheckService if the whole check task is already cancelled —
        // the fallback would also be cancelled immediately, wasting work and producing noisy logs.
        guard !Task.isCancelled else { return [] }

        logger.info("resolveSpellIssues: AI unavailable or timed out — falling back to SpellCheckService")
        return await SpellCheckService.check(text: text)
    }

    func runCheck() async {
        logger.debug("runCheck: starting spell check (text length: \(self.text.count))")
        let currentText = text

        // Snapshot preferences before async work
        let prefs = PreferencesManager.shared
        let formality = prefs.formalityLevel
        let audience = prefs.audienceLevel
        let disabledRules = prefs.disabledRules

        // Spell check: AI first (when configured), NSSpellChecker fallback
        // NL analysis + rule engine: both moved off @MainActor so they don't block
        // SwiftUI layout or input handling (NLTagger init is 50-200 ms on first use).
        async let spellIssues = resolveSpellIssues(text: currentText)
        let (analysis, ruleIssues) = await Task.detached(priority: .userInitiated) {
            let analysis = NLAnalysisService.analyze(
                currentText,
                formality: formality,
                audience: audience
            )
            let ruleIssues = RuleRegistry.runAll(
                text: currentText,
                analysis: analysis,
                disabledRules: disabledRules
            )
            return (analysis, ruleIssues)
        }.value

        let detected = await spellIssues + ruleIssues
        guard !Task.isCancelled else {
            logger.debug("runCheck: cancelled after checks returned")
            return
        }

        cachedAnalysis = analysis
        logger.debug("runCheck: checks complete — \(detected.count) raw issues")

        // Record stats
        WritingStatsStore.shared.recordWordCount(wordCount)
        for issue in detected {
            WritingStatsStore.shared.recordIssue(type: issue.type)
        }

        // Filter out persistent ignores and session ignores
        let ignoreStore = IgnoreRulesStore.shared
        let newIssues = detected.filter {
            !ignoredRanges.contains(ignoredKey(for: $0))
            && !ignoreStore.isIgnored(word: $0.word, ruleID: $0.type.categoryLabel)
        }

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
        WritingStatsStore.shared.recordCorrection()

        // Save existing clipboard content so we can restore it if the paste fallback fires.
        // The AX injection path never touches the clipboard, so the user's copied content
        // is preserved whenever AX succeeds (the common case).
        let previousClipboard = NSPasteboard.general.string(forType: .string)

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
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(correction, forType: .string)
            Self.simulatePasteStatic()
            if let prev = previousClipboard {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prev, forType: .string)
                }
            }
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
                DispatchQueue.main.async {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(correction, forType: .string)
                    Self.simulatePasteStatic()
                    if let prev = previousClipboard {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(prev, forType: .string)
                        }
                    }
                }
            }
            Task { @MainActor in
                self?.isCorrectionInFlight = false
                logger.debug("applyCorrection: correctionInFlight cleared (normal path)")
            }
        }
        logger.debug("applyCorrection: Phase 1 complete, background AX dispatched [END sync]")
    }

    /// Applies a snippet expansion: replaces the typed trigger with the full expansion
    /// text using the same AX-injection + clipboard-paste fallback strategy as
    /// `applyCorrection(_:correction:)`.
    func applySnippet(_ snippet: Snippet) {
        logger.info("applySnippet: '\(snippet.trigger)' → '\(snippet.expansion)' [START]")

        guard !isCorrectionInFlight else {
            logger.warning("applySnippet: correction already in flight — skipping")
            return
        }

        isCorrectionInFlight = true
        lastCorrectionTime = .now

        // Save existing clipboard content so we can restore it if the paste fallback fires.
        let previousClipboard = NSPasteboard.general.string(forType: .string)
        logger.debug("applySnippet: previous clipboard saved")

        // Update the input monitor's buffer so the trigger doesn't re-fire on the
        // next word boundary. Mark as programmatic so hudShownKeys is preserved.
        isProgrammaticBufferUpdate = true
        inputMonitor?.replaceInBuffer(old: snippet.trigger, new: snippet.expansion)
        isProgrammaticBufferUpdate = false
        logger.debug("applySnippet: buffer updated")

        let trigger = snippet.trigger
        let expansion = snippet.expansion

        let fallbackItem = DispatchWorkItem { [weak self] in
            logger.warning("applySnippet: AX timed out — firing paste fallback")
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(expansion, forType: .string)
            Self.simulatePasteStatic()
            if let prev = previousClipboard {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prev, forType: .string)
                }
            }
            Task { @MainActor in
                self?.isCorrectionInFlight = false
                logger.debug("applySnippet: correctionInFlight cleared (timeout path)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: fallbackItem)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            logger.debug("applySnippet: AX injection starting on background thread")
            let axSucceeded = Self.injectCorrectionViaAXBackground(
                word: trigger, correction: expansion
            )
            logger.info("applySnippet: AX injection result = \(axSucceeded)")
            fallbackItem.cancel()
            if !axSucceeded {
                logger.warning("applySnippet: AX failed — firing paste fallback")
                DispatchQueue.main.async {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(expansion, forType: .string)
                    Self.simulatePasteStatic()
                    if let prev = previousClipboard {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(prev, forType: .string)
                        }
                    }
                }
            }
            Task { @MainActor in
                self?.isCorrectionInFlight = false
                logger.debug("applySnippet: correctionInFlight cleared (normal path)")
            }
        }
        logger.debug("applySnippet: Phase 1 complete, background AX dispatched [END sync]")
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

    /// Replaces the currently selected text in the focused application.
    /// Used by `SelectionSuggestionPanel` when applying an AI-suggested rewrite.
    /// Unlike `applyCorrection(_:correction:)`, this works with arbitrary selections —
    /// it sets `kAXSelectedTextAttribute` directly rather than searching for a word.
    func replaceSelection(replacement: String) {
        logger.info("replaceSelection: '\(replacement.prefix(40))' [START]")

        isCorrectionInFlight = true
        lastCorrectionTime = .now

        // Save existing clipboard content so we can restore it if the paste fallback fires.
        let previousClipboard = NSPasteboard.general.string(forType: .string)

        let fallbackItem = DispatchWorkItem { [weak self] in
            logger.warning("replaceSelection: AX timed out — firing paste fallback")
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(replacement, forType: .string)
            Self.simulatePasteStatic()
            if let prev = previousClipboard {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prev, forType: .string)
                }
            }
            Task { @MainActor in
                self?.isCorrectionInFlight = false
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: fallbackItem)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let axSucceeded = Self.injectSelectedTextViaAXBackground(replacement: replacement)
            fallbackItem.cancel()
            if !axSucceeded {
                logger.warning("replaceSelection: AX failed — firing paste fallback")
                DispatchQueue.main.async {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(replacement, forType: .string)
                    Self.simulatePasteStatic()
                    if let prev = previousClipboard {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(prev, forType: .string)
                        }
                    }
                }
            }
            Task { @MainActor in
                self?.isCorrectionInFlight = false
                logger.debug("replaceSelection: correctionInFlight cleared")
            }
        }
    }

    /// Replaces the currently selected text in the focused UI element.
    /// Sets `kAXSelectedTextAttribute` directly — the selection must already exist
    /// in the target app (the panel is non-activating, so the original selection persists).
    private nonisolated static func injectSelectedTextViaAXBackground(replacement: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            logger.warning("replaceSelection AX-bg: no focused element")
            return false
        }
        let element = focusedRef as! AXUIElement // safe: type ID verified above
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            replacement as CFString
        )
        logger.debug("replaceSelection AX-bg: result = \(result == .success ? "success" : "failed")")
        return result == .success
    }

    func ignoreIssue(_ issue: WritingIssue) {
        ignoredRanges.insert(ignoredKey(for: issue))
        issues.removeAll { $0.id == issue.id }
    }

    private func ignoredKey(for issue: WritingIssue) -> String {
        "\(issue.word):\(issue.range.location)"
    }
}
