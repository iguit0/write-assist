// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import os

private let logger = Logger(subsystem: "com.writeassist", category: "GlobalInputMonitor")

/// Monitors global keyboard events across all applications and feeds
/// accumulated text into the shared `DocumentViewModel`.
@MainActor
@Observable
public final class GlobalInputMonitor {

    // MARK: - Observable State

    public private(set) var hasAccessibilityPermission = false

    // MARK: - Private State

    private var monitor: Any?
    private var buffer: [Character] = []
    private let maxBufferSize = 500
    weak var viewModel: DocumentViewModel?

    /// Set after Cmd+A (Select All). The next destructive keystroke (Delete,
    /// typing a character) clears the buffer since the entire selection is
    /// being replaced. Reset when a non-destructive event is seen.
    private var pendingSelectAll = false

    /// Called immediately on every keystroke (before debounce/spell-check).
    /// Used by StatusBarController to dismiss the inline suggestion popup instantly.
    var onKeystroke: (() -> Void)?

    /// Called when a word-completing key (space, punctuation, Return) is pressed
    /// immediately after a word character. Used by ExternalSpellChecker to schedule
    /// a real-time spell check with an 800 ms debounce.
    var onWordBoundaryTyped: (() -> Void)?

    /// Fires when Accessibility permission changes (granted or revoked).
    var onAccessibilityPermissionChanged: ((Bool) -> Void)?

    // MARK: - Polling Timer

    private var permissionTimer: Timer?

    // MARK: - Init

    public init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
        checkPermission()
        startPermissionPolling()
    }

    /// Invalidates the permission polling timer. Call before releasing this object.
    /// Marked `@MainActor` to allow direct synchronous access to the timer.
    @MainActor
    public func cleanup() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    // MARK: - Permissions

    func checkPermission() {
        let trusted = AXIsProcessTrusted()
        let wasPermitted = hasAccessibilityPermission
        hasAccessibilityPermission = trusted

        if trusted && !wasPermitted {
            // Permission just granted (or first check succeeds) — start monitoring
            startMonitoring()
            onAccessibilityPermissionChanged?(true)
        } else if !trusted && wasPermitted {
            // Permission just revoked — stop monitoring and clear buffer
            stopMonitoring()
            buffer.removeAll()
            viewModel?.textDidChange("")
            onAccessibilityPermissionChanged?(false)
        }
    }

    /// Polls every 3 seconds to detect permission changes in real time.
    /// This lets the UI react immediately when the user grants or revokes access.
    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermission()
            }
        }
    }

    func requestPermission() {
        // Open System Settings > Privacy > Accessibility so user can enable it.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Monitoring

    public func startMonitoring() {
        guard AXIsProcessTrusted(), monitor == nil else { return }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event)
            }
        }
    }

    public func stopMonitoring() {
        if let existingMonitor = monitor {
            NSEvent.removeMonitor(existingMonitor)
        }
        monitor = nil
    }

    // MARK: - Event Handling

    private func handle(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])

        // ── Track text-modifying shortcuts ────────────────────────────────────
        // These invalidate the buffer because they change the target app's text
        // in ways keystroke-by-keystroke tracking can't follow.
        if modifiers.contains(.command) {
            onKeystroke?()
            let keyCode = event.keyCode
            switch keyCode {
            case 0:  // Cmd+A — Select All
                logger.debug("handle: Cmd+A detected — setting pendingSelectAll")
                pendingSelectAll = true
            case 6:  // Cmd+Z — Undo (buffer unreliable after undo)
                logger.debug("handle: Cmd+Z — clearing buffer (undo)")
                pendingSelectAll = false
                buffer.removeAll()
                viewModel?.textDidChange("")
            case 7:  // Cmd+X — Cut (removes selected text)
                if pendingSelectAll {
                    logger.debug("handle: Cmd+X after Select All — clearing buffer")
                    pendingSelectAll = false
                    buffer.removeAll()
                    viewModel?.textDidChange("")
                }
            case 9:  // Cmd+V — Paste (inserts unknown text)
                if pendingSelectAll {
                    logger.debug("handle: Cmd+V after Select All — clearing buffer (paste replaces all)")
                    pendingSelectAll = false
                    buffer.removeAll()
                    viewModel?.textDidChange("")
                }
                // Note: pasted text won't appear in buffer — next spell check
                // won't see it. This is a known limitation of keystroke monitoring.
            default:
                break
            }
            return
        }

        // Ignore other modifier combos (Ctrl+key, Option+key)
        guard modifiers.isEmpty else { return }

        // Notify immediately (before buffering) so popups can dismiss without delay
        onKeystroke?()

        let keyCode = event.keyCode

        // ── Handle pendingSelectAll ──────────────────────────────────────────
        // If Cmd+A was pressed and the user now types or deletes, the entire
        // selected text in the target app is replaced. Clear the buffer first.
        if pendingSelectAll {
            pendingSelectAll = false
            switch keyCode {
            case 51: // Delete after Select All — everything is gone
                logger.debug("handle: Delete after Select All — clearing buffer")
                buffer.removeAll()
                viewModel?.textDidChange("")
                return
            default:
                // Any printable character after Select All replaces everything
                logger.debug("handle: typing after Select All — clearing buffer, then adding character")
                buffer.removeAll()
                // Fall through to add the typed character below
            }
        }

        // Capture the last buffer character BEFORE processing this key.
        // Used below to detect word boundaries: a word is complete when the
        // character just typed is a boundary (space / punctuation / Return) and
        // the preceding character was part of a word.
        let lastCharBeforeKey = buffer.last

        switch keyCode {
        case 51: // Delete (backspace)
            if !buffer.isEmpty {
                buffer.removeLast()
            }
        case 36, 76: // Return / Enter
            buffer.append("\n")
        case 53: // Escape — clear buffer
            buffer.removeAll()
        case 48: // Tab
            buffer.append("\t")
        default:
            guard let chars = event.characters, !chars.isEmpty else { return }
            // Only append printable/typeable characters (letters, numbers, punctuation, symbols, whitespace)
            for char in chars where char.isLetter || char.isNumber
                || char.isPunctuation || char.isSymbol || char.isWhitespace {
                buffer.append(char)
            }
        }

        // Fire word-boundary callback when the user completes a word.
        // Condition: the character just processed is a boundary AND the character
        // before it was a word character (letter or digit).
        if lastCharBeforeKey?.isLetter == true || lastCharBeforeKey?.isNumber == true {
            let isBoundaryKey: Bool
            switch keyCode {
            case 36, 76: // Return / Enter
                isBoundaryKey = true
            case 48: // Tab
                isBoundaryKey = true
            default:
                // Space, period, comma, ?, !, ;, : all end words.
                isBoundaryKey = event.characters?.first.map { c in
                    c == " " || c == "." || c == "," || c == "?"
                        || c == "!" || c == ";" || c == ":"
                } ?? false
            }
            if isBoundaryKey {
                logger.debug("handle: word boundary after '\(String(lastCharBeforeKey!), privacy: .sensitive)'")
                onWordBoundaryTyped?()
            }
        }

        // Trim buffer to max size
        if buffer.count > maxBufferSize {
            buffer = Array(buffer.suffix(maxBufferSize))
        }

        let text = String(buffer)
        viewModel?.textDidChange(text)
    }

    // MARK: - Buffer

    var capturedText: String {
        String(buffer)
    }

    func clearBuffer() {
        buffer.removeAll()
        viewModel?.textDidChange("")
    }

    /// Replaces the last occurrence of `old` in the buffer with `new`.
    /// Called after a correction is applied so the buffer reflects the corrected text
    /// and subsequent spell checks don't re-detect the already-corrected word.
    func replaceInBuffer(old: String, new: String) {
        logger.debug("replaceInBuffer: old=\(old.count) chars → new=\(new.count) chars")
        let text = String(buffer)
        // Find the last occurrence of the old word in the current buffer text
        guard let range = text.range(of: old, options: .backwards) else {
            logger.warning("replaceInBuffer: word (length: \(old.count)) not found in buffer")
            return
        }
        let corrected = text.replacingCharacters(in: range, with: new)
        buffer = Array(corrected)
        // Trim to max buffer size if needed
        if buffer.count > maxBufferSize {
            buffer = Array(buffer.suffix(maxBufferSize))
        }
        // Notify the view model of the updated text so spell check runs on corrected content
        logger.debug("replaceInBuffer: calling textDidChange (buffer length: \(self.buffer.count))")
        viewModel?.textDidChange(corrected)
    }
}
