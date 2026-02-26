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

    /// Set to false when the screensaver starts or the Mac sleeps, to skip
    /// AX polls while the display is inactive and avoid unnecessary battery drain (#038).
    private var isScreenActive = true

    /// Opaque observer tokens from `NSWorkspace.notificationCenter`.
    /// Held so they can be removed when the monitor stops.
    private var workspaceObservers: [AnyObject] = []

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
        registerScreenObservers()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // Skip polls while the screen is off to avoid unnecessary AX calls (#038)
                if self?.isScreenActive == true {
                    await self?.poll()
                }
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
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObservers.removeAll()
        logger.debug("SelectionMonitor: stopped")
    }

    // MARK: - Screen-state observers

    /// Registers NSWorkspace notifications for system sleep and wake events
    /// so the polling loop can be paused when the Mac is sleeping (#038).
    /// Note: screensaver-specific notifications require DistributedNotificationCenter
    /// and are not included here; system sleep covers the primary battery-drain case.
    private func registerScreenObservers() {
        guard workspaceObservers.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter

        let sleepNames: [NSNotification.Name] = [
            NSWorkspace.willSleepNotification
        ]
        let wakeNames: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification
        ]

        for name in sleepNames {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isScreenActive = false
                    logger.debug("SelectionMonitor: system sleeping — AX polling paused")
                }
            }
            workspaceObservers.append(token)
        }

        for name in wakeNames {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isScreenActive = true
                    logger.debug("SelectionMonitor: system awake — AX polling resumed")
                }
            }
            workspaceObservers.append(token)
        }
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

    // MARK: - AX Read (background, nonisolated) — uses AXHelper (#020)

    private nonisolated static func readSelection() -> (String, NSRange, CGRect)? {
        // Skip elements belonging to this process (WriteAssist's own popover).
        guard let element = AXHelper.focusedElement(skipSelf: true) else { return nil }

        // Read selected text.
        guard let text = AXHelper.selectedText(of: element) else { return nil }

        // Read selected range as AXValue.
        guard let rangeRef = AXHelper.selectedRangeRef(of: element) else { return nil }

        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &cfRange) else { return nil }
        let nsRange = NSRange(location: cfRange.location, length: cfRange.length)

        // Read screen bounds for panel positioning (best-effort; use .zero on failure).
        let bounds = AXHelper.bounds(for: rangeRef, in: element) ?? .zero

        return (text, nsRange, bounds)
    }
}
