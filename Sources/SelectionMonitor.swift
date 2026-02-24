// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

@preconcurrency import AppKit
import os

private let logger = Logger(subsystem: "com.writeassist", category: "SelectionMonitor")

/// Polls the Accessibility API every 250 ms to detect when the user selects
/// text in any application. Fires `onSelectionChanged` when a qualifying selection
/// is made (≥ 3 words or ≥ 15 characters), and `onSelectionCleared` when the
/// selection drops back to empty.
@MainActor
final class SelectionMonitor {

    /// Called when a selection meeting the threshold is detected.
    /// Receives: (selectedText, NSRange in source text, selection bounds in AX screen coords)
    var onSelectionChanged: ((String, NSRange, CGRect) -> Void)?

    /// Called when the selection is cleared after having been non-empty.
    var onSelectionCleared: (() -> Void)?

    /// Key of the last selection we fired `onSelectionChanged` for.
    /// Prevents re-firing for the same unchanged selection.
    private var lastSelectionKey = ""

    private var pollingTask: Task<Void, Never>?

    // MARK: - Thresholds

    private let minCharCount = 15
    private let minWordCount = 3

    // MARK: - Lifecycle

    func start() {
        // Guard on AX permission — without it every poll dispatches a background
        // thread that returns kAXErrorAPIDisabled immediately, wasting CPU for nothing.
        // StatusBarController re-calls start() whenever permission is detected.
        guard AXIsProcessTrusted() else {
            logger.debug("SelectionMonitor: AX permission not granted — skipping start")
            return
        }
        guard pollingTask == nil else { return }
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    break
                }
            }
        }
        logger.debug("SelectionMonitor: started")
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        lastSelectionKey = ""
        logger.debug("SelectionMonitor: stopped")
    }

    // MARK: - Polling

    private func poll() async {
        // Read AX selection on a background thread (AX reads are fast but blocking).
        let result = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.readSelection())
            }
        }

        guard let (text, range, bounds) = result else {
            // No selection — fire cleared callback if we were tracking one.
            if !lastSelectionKey.isEmpty {
                lastSelectionKey = ""
                logger.debug("SelectionMonitor: selection cleared")
                onSelectionCleared?()
            }
            return
        }

        // Require at least one letter — filters out whitespace-only (tab indentation,
        // blank lines) and numeric-only (page numbers, codes) selections that would
        // waste an AI rewrite request for meaningless content.
        guard text.contains(where: { $0.isLetter }) else {
            if !lastSelectionKey.isEmpty {
                lastSelectionKey = ""
                onSelectionCleared?()
            }
            return
        }

        // Apply threshold: must be ≥ 3 words OR ≥ 15 chars.
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        guard text.count >= minCharCount || wordCount >= minWordCount else {
            if !lastSelectionKey.isEmpty {
                lastSelectionKey = ""
                onSelectionCleared?()
            }
            return
        }

        // Only fire if the selection actually changed.
        let key = "\(range.location):\(range.length)"
        guard key != lastSelectionKey else { return }
        lastSelectionKey = key

        logger.debug("SelectionMonitor: selection '\(text.prefix(40))' at \(range.location)+\(range.length)")
        onSelectionChanged?(text, range, bounds)
    }

    // MARK: - AX Read (background, nonisolated)

    private nonisolated static func readSelection() -> (String, NSRange, CGRect)? {
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

        // Skip selections inside WriteAssist itself (e.g., the popover's HighlightedTextView)
        // to prevent the system-wide panel from appearing over WriteAssist's own UI.
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if pid == ProcessInfo.processInfo.processIdentifier { return nil }

        // Read the selected text string.
        var textRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &textRef
        ) == .success,
              let textRef,
              let text = textRef as? String,
              !text.isEmpty
        else { return nil }

        // Read the selected range.
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeRef else { return nil }

        var cfRange = CFRange(location: 0, length: 0)
        // Safe to force-cast: kAXSelectedTextRangeAttribute always returns an AXValue.
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &cfRange) else { return nil }
        let nsRange = NSRange(location: cfRange.location, length: cfRange.length)

        // Read screen bounds for panel positioning (best-effort; use .zero on failure).
        var boundsRef: CFTypeRef?
        var bounds = CGRect.zero
        if AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef,
            &boundsRef
        ) == .success,
           let boundsRef {
            // Safe to force-cast: kAXBoundsForRangeParameterizedAttribute returns AXValue.
            AXValueGetValue(boundsRef as! AXValue, .cgRect, &bounds)
        }

        return (text, nsRange, bounds)
    }
}
