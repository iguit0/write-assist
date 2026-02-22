// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import os

private let logger = Logger(subsystem: "com.writeassist", category: "GlobalInputMonitor")

/// Monitors global keyboard events across all applications and feeds
/// accumulated text into the shared `DocumentViewModel`.
@MainActor
@Observable
final class GlobalInputMonitor {

    // MARK: - Observable State

    private(set) var hasAccessibilityPermission = false

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

    /// Called when a snippet trigger is detected in the buffer.
    var onSnippetTriggered: ((Snippet) -> Void)?

    // MARK: - Polling Timer

    private var permissionTimer: Timer?

    // MARK: - Init

    init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
        checkPermission()
        startPermissionPolling()
    }

    /// Invalidates the permission polling timer. Call before releasing this object.
    /// Marked `@MainActor` to allow direct synchronous access to the timer.
    @MainActor
    func cleanup() {
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
        } else if !trusted && wasPermitted {
            // Permission just revoked — stop monitoring and clear buffer
            stopMonitoring()
            buffer.removeAll()
            viewModel?.textDidChange("")
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

    func startMonitoring() {
        guard AXIsProcessTrusted(), monitor == nil else { return }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event)
            }
        }
    }

    func stopMonitoring() {
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

        // Trim buffer to max size
        if buffer.count > maxBufferSize {
            buffer = Array(buffer.suffix(maxBufferSize))
        }

        let text = String(buffer)
        viewModel?.textDidChange(text)

        // Check for snippet trigger
        checkSnippetTrigger(text: text)
    }

    private func checkSnippetTrigger(text: String) {
        if let snippet = SnippetsManager.shared.matchingSnippet(for: text) {
            onSnippetTriggered?(snippet)
        }
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
        logger.debug("replaceInBuffer: '\(old)' → '\(new)'")
        let text = String(buffer)
        // Find the last occurrence of the old word in the current buffer text
        guard let range = text.range(of: old, options: .backwards) else {
            logger.warning("replaceInBuffer: '\(old)' not found in buffer")
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
