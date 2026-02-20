// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import os
import SwiftUI

private let logger = Logger(subsystem: "com.writeassist", category: "ErrorHUDPanel")

/// A non-activating floating panel that appears near the text cursor when
/// a new writing error is detected — Grammarly-style inline suggestion popup.
/// Shows the issue word, type, message, and up to 4 suggestion buttons.
/// Dismisses when the user types, clicks a suggestion, or clicks Ignore/×.
@MainActor
final class ErrorHUDPanel {
    private var panel: NSPanel?

    /// Incremented on each `show()` call so an in-flight async position query
    /// from a previous invocation doesn't present a stale panel.
    private var showGeneration = 0

    /// Timestamp of the last dismiss. Used to enforce a minimum gap between
    /// dismiss and the next show, preventing rapid HUD cycling.
    private var lastDismissTime: ContinuousClock.Instant?

    /// Minimum gap between dismiss and next show.
    private let showCooldown: Duration = .seconds(1.0)

    // MARK: - Public API

    /// Show the inline suggestion popup anchored near the text cursor.
    /// Queries caret bounds via Accessibility on a background thread, then
    /// positions the panel just below the caret. Falls back to the top-right
    /// corner of the screen if the AX query fails.
    func show(issue: WritingIssue, viewModel: DocumentViewModel) {
        // ── Cooldown gate ────────────────────────────────────────────────────
        // Don't show a new HUD if we just dismissed one (prevents rapid cycling
        // that leads to competing AX calls and deadlocks).
        if let lastDismiss = lastDismissTime,
           ContinuousClock.now - lastDismiss < showCooldown {
            logger.debug("show: skipping — within cooldown (\(issue.word))")
            return
        }

        // ── Correction-in-flight gate ────────────────────────────────────────
        // Don't show while an AX injection is active — the caret query would
        // compete with the correction's AX writes on the same element.
        if viewModel.isCorrectionInFlight {
            logger.debug("show: skipping — correction in flight (\(issue.word))")
            return
        }

        logger.info("show: presenting HUD for '\(issue.word)'")

        // Force-remove any panel including one mid-fade-out animation
        panel?.alphaValue = 0
        panel?.orderOut(nil)
        panel = nil

        showGeneration &+= 1
        let generation = showGeneration

        let contentView = InlineSuggestionView(issue: issue) { [weak self, weak viewModel] suggestion in
            logger.debug("onApply: user selected '\(suggestion)' for '\(issue.word)'")
            // Dismiss first (starts fade-out animation), then apply correction.
            self?.dismiss()
            viewModel?.applyCorrection(issue, correction: suggestion)
        } onIgnore: { [weak self, weak viewModel] in
            logger.debug("onIgnore: user ignored '\(issue.word)'")
            viewModel?.ignoreIssue(issue)
            self?.dismiss()
        } onDismiss: { [weak self] in
            logger.debug("onDismiss: user dismissed HUD")
            self?.dismiss()
        }

        // Force a layout pass before reading fittingSize so SwiftUI has had a
        // chance to measure the view. Without this, fittingSize can return zero.
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 280, height: 400))
        hostingView.layout()
        let fittingSize = hostingView.fittingSize
        let hudSize = NSSize(
            width: max(fittingSize.width, 280),
            height: max(fittingSize.height, 80)
        )
        hostingView.frame = NSRect(origin: .zero, size: hudSize)

        // Query the text caret position off the main thread, then present.
        Task { @MainActor [weak self] in
            logger.debug("show: querying caret bounds async")
            let caretBounds = await Self.queryCaretBoundsAsync()
            logger.debug("show: caret query returned (has bounds: \(caretBounds != nil))")
            guard let self, self.showGeneration == generation else {
                logger.debug("show: stale generation — aborting")
                return
            }
            // Bail if a newer show() call already placed a panel
            guard self.panel == nil else {
                logger.debug("show: panel already exists — aborting")
                return
            }

            let origin: NSPoint
            if let caretBounds {
                origin = Self.caretAnchoredOrigin(caretBounds: caretBounds, hudSize: hudSize)
            } else {
                origin = Self.topRightFallbackOrigin(hudSize: hudSize)
            }

            logger.debug("show: presenting panel at (\(origin.x), \(origin.y))")
            self.presentPanel(hostingView: hostingView, size: hudSize, origin: origin)
        }
    }

    /// Fade out and remove the HUD panel.
    func dismiss() {
        guard let p = panel else { return }
        logger.debug("dismiss: fading out HUD panel")
        panel = nil
        lastDismissTime = .now
        // Stop any in-flight fade-in before starting fade-out
        let currentAlpha = p.alphaValue
        p.animator().alphaValue = currentAlpha
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            p.animator().alphaValue = 0
        }, completionHandler: {
            // NSAnimationContext completion blocks run on the main thread,
            // but we use Task to be explicit and avoid assumeIsolated crashing
            // if Apple ever changes that contract.
            Task { @MainActor in p.orderOut(nil) }
        })
    }

    // MARK: - Panel Presentation

    /// Creates and fades in the HUD panel at the given origin.
    private func presentPanel(hostingView: NSView, size: NSSize, origin: NSPoint) {
        let p = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        // Use .floating instead of .statusBar — .statusBar sits at the same level
        // as the macOS menu bar and can intercept clicks on the status bar button.
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false // InlineSuggestionView applies its own SwiftUI shadow
        p.contentView = hostingView
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.alphaValue = 0

        panel = p
        p.orderFrontRegardless()

        // Fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 1
        }
    }

    // MARK: - Panel Positioning

    /// Positions the HUD just below the text caret, clamped to the visible
    /// area of the screen containing the caret. If the HUD would overflow
    /// below the visible area, it flips above the caret instead.
    ///
    /// - Parameters:
    ///   - caretBounds: Caret rectangle in AX screen coordinates (top-left origin).
    ///   - hudSize: Measured size of the HUD content.
    private static func caretAnchoredOrigin(caretBounds: CGRect, hudSize: NSSize) -> NSPoint {
        // AX uses top-left origin; AppKit uses bottom-left origin.
        // Primary screen height is the reference for coordinate conversion.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900

        // Convert AX rect edges to AppKit Y coordinates
        let caretTopAppKit = primaryHeight - caretBounds.minY
        let caretBottomAppKit = primaryHeight - caretBounds.maxY
        let caretX = caretBounds.origin.x

        // Find the screen containing the caret center
        let caretCenter = NSPoint(
            x: caretX + caretBounds.width / 2,
            y: (caretTopAppKit + caretBottomAppKit) / 2
        )
        let screen = NSScreen.screens.first { $0.frame.contains(caretCenter) }
        let visibleFrame = screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let gap: CGFloat = 4

        // Try placing HUD below the caret
        var y = caretBottomAppKit - gap - hudSize.height

        // If it would go below the visible area, place above the caret instead
        if y < visibleFrame.minY {
            y = caretTopAppKit + gap
        }

        // X: align with caret left edge, clamped to visible area
        var x = caretX
        x = max(visibleFrame.minX + 8, min(x, visibleFrame.maxX - hudSize.width - 8))

        // Final Y clamp
        y = max(visibleFrame.minY, min(y, visibleFrame.maxY - hudSize.height))

        return NSPoint(x: x, y: y)
    }

    /// Fallback: positions the HUD at the top-right corner of the main screen.
    private static func topRightFallbackOrigin(hudSize: NSSize) -> NSPoint {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(
            x: screenFrame.maxX - hudSize.width - 16,
            y: screenFrame.maxY - hudSize.height - 8
        )
    }

    // MARK: - Caret Position via Accessibility

    /// Queries the caret bounds on a background thread to avoid blocking @MainActor.
    /// AX read-only calls are fast (< 50ms typically), unlike write calls which can
    /// hang indefinitely on some apps.
    private static func queryCaretBoundsAsync() async -> CGRect? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                logger.debug("queryCaretBounds: starting on background thread")
                let result = queryCaretBounds()
                logger.debug("queryCaretBounds: completed (got bounds: \(result != nil))")
                continuation.resume(returning: result)
            }
        }
    }

    /// Returns the screen bounds (AX coordinates: top-left origin) of the text
    /// caret in the currently focused UI element. Returns nil on failure.
    private nonisolated static func queryCaretBounds() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else {
            logger.debug("queryCaretBounds: no focused element")
            return nil
        }
        let element = focusedRef as! AXUIElement

        // Get the selected text range (caret position)
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeRef else {
            logger.debug("queryCaretBounds: no selected text range")
            return nil
        }

        // Get screen bounds for the caret range
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef,
            &boundsRef
        ) == .success, let boundsRef else {
            logger.debug("queryCaretBounds: no bounds for range")
            return nil
        }

        var rect = CGRect.zero
        // Safe to force-cast: AXValueCreate always returns an AXValue for this attribute
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else { return nil }

        return rect
    }
}

// MARK: - Inline Suggestion Content View

/// The rich inline popup content — reuses SuggestionPopover layout with a
/// frosted glass background and subtle colored border.
private struct InlineSuggestionView: View {
    let issue: WritingIssue
    let onApply: (String) -> Void
    let onIgnore: () -> Void
    let onDismiss: () -> Void

    @State private var hoveredSuggestion: String?

    private var accentColor: Color {
        issue.type == .spelling ? .red : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(width: 3, height: 14)
                Text(issue.type == .spelling ? "Spelling" : "Grammar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(issue.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                // Dismiss "×" button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .padding(4)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider().padding(.horizontal, 8)

            // Word display
            Text("\"\(issue.word)\"")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // Suggestions list or placeholder
            if issue.suggestions.isEmpty {
                Text("No suggestions available")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(issue.suggestions.prefix(4), id: \.self) { suggestion in
                        Button {
                            onApply(suggestion)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(accentColor)
                                    .frame(width: 12)
                                Text(suggestion)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(
                                    hoveredSuggestion == suggestion ? 0.07 : 0.0
                                ))
                        )
                        .onHover { isHovered in
                            hoveredSuggestion = isHovered ? suggestion : nil
                        }
                    }
                }
                .padding(.top, 4)
            }

            Divider().padding(.horizontal, 8).padding(.top, 4)

            // Ignore button
            Button(action: onIgnore) {
                HStack(spacing: 5) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10))
                    Text("Ignore")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.3), lineWidth: 0.75)
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
        .padding(2) // prevent shadow clipping
    }
}
