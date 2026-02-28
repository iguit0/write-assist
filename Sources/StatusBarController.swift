// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import CoreGraphics
import os
import SwiftUI

private let logger = Logger(subsystem: "com.writeassist", category: "StatusBarController")

/// Manages the macOS menu bar status item and attaches an `NSPopover`
/// containing the WriteAssist suggestions panel.
///
/// All mutable state is on `@MainActor`. `@unchecked Sendable` is required
/// for callbacks captured across actor boundaries in Task closures.
@MainActor
public final class StatusBarController: NSObject, @unchecked Sendable {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var hudPanel: ErrorHUDPanel?
    private var selectionPanel: SelectionSuggestionPanel?
    private var selectionMonitor: SelectionMonitor?
    private var externalSpellChecker: ExternalSpellChecker?
    private var isAnimating = false
    private var hotkeyEventTap: CFMachPort?
    private var hotkeyMonitor: Any?

    // MARK: - Setup

    private weak var viewModel: DocumentViewModel?
    private var badgeObserver: Task<Void, Never>?

    public override init() { super.init() }

    public func setup(viewModel: DocumentViewModel, inputMonitor: GlobalInputMonitor) {
        self.viewModel = viewModel
        hudPanel = ErrorHUDPanel()
        selectionPanel = SelectionSuggestionPanel(viewModel: viewModel)

        // Create the status bar item — use variableLength so the button
        // is always visible even if the image fails to load.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.wantsLayer = true
            // SF Symbol lookup can return nil when running without a bundle
            // (common in SPM-built apps). Use a Unicode emoji as a guaranteed
            // fallback so the menu bar item is always visible.
            // Try multiple symbol names in order of availability,
            // fall back to emoji if none resolve (common in SPM builds).
            let symbolNames = ["pencil.and.sparkles", "pencil.circle.fill", "pencil"]
            var resolved = false
            for name in symbolNames {
                if let img = NSImage(systemSymbolName: name,
                                     accessibilityDescription: "WriteAssist") {
                    img.isTemplate = true
                    button.image = img
                    resolved = true
                    break
                }
            }
            if !resolved {
                button.title = "✏️"
            }
            button.action = #selector(StatusBarController.togglePopover)
            button.target = self
        }
        statusItem = item

        // Watch for issue count changes and update the badge
        startBadgeObserver(viewModel: viewModel)

        // Real-time external spell checking — fires 800 ms after the user completes
        // a word in any external app (space/punctuation/Return after a word character).
        let spellChecker = ExternalSpellChecker()
        externalSpellChecker = spellChecker
        spellChecker.onIssueDetected = { [weak self, weak viewModel] issue, caretBounds in
            guard let self, let viewModel else { return }
            // Don't show if the sidebar popover is visible
            guard self.popover?.isShown != true else { return }
            // Don't show while an AX correction is being applied
            guard !viewModel.isCorrectionInFlight else { return }
            // Don't show while the HUD keyboard nav is active
            guard self.hudPanel?.isAcceptingKeyboardInput != true else { return }
            // Don't stack on top of the selection suggestion panel
            guard self.selectionPanel?.isVisible != true else { return }
            self.hudPanel?.show(issue: issue, viewModel: viewModel)
        }

        inputMonitor.onWordBoundaryTyped = { [weak spellChecker, weak viewModel] in
            // Skip if correction is in flight — reading AX now would race with the write.
            guard viewModel?.isCorrectionInFlight != true else { return }
            spellChecker?.scheduleCheck()
        }

        // Show the selection panel when the user selects ≥ 3 words in any app.
        // Guards: don't show while the sidebar is open, the HUD is in keyboard-nav
        // mode, or a correction is being applied.
        let monitor = SelectionMonitor()
        selectionMonitor = monitor
        monitor.onSelectionChanged = { [weak self, weak viewModel] text, range, bounds in
            guard let self else { return }
            guard self.popover?.isShown != true else { return }
            guard self.hudPanel?.isAcceptingKeyboardInput != true else { return }
            guard viewModel?.isCorrectionInFlight != true else { return }
            self.selectionPanel?.show(selectedText: text, range: range, near: bounds)
        }
        monitor.onSelectionCleared = { [weak self] in
            self?.selectionPanel?.dismiss()
        }
        monitor.start()

        // Direct callback: fires from runCheck() as soon as spell-check completes —
        // no polling lag. Shows the HUD for the first issue in the list.
        viewModel.onNewIssuesReadyForHUD = { [weak self] issues in
            guard let self else { return }
            // Don't show HUD if the sidebar popover is already visible
            guard self.popover?.isShown != true else {
                logger.debug("onNewIssuesReadyForHUD: popover visible — skipping HUD")
                return
            }
            // Don't show HUD while the selection suggestion panel is on screen —
            // both panels use floating NSPanel and would stack confusingly.
            guard self.selectionPanel?.isVisible != true else {
                logger.debug("onNewIssuesReadyForHUD: selection panel visible — skipping HUD")
                return
            }
            // Don't show HUD while a correction is being applied
            guard !viewModel.isCorrectionInFlight else {
                logger.debug("onNewIssuesReadyForHUD: correction in flight — skipping HUD")
                return
            }
            if let first = issues.first {
                logger.info("onNewIssuesReadyForHUD: showing HUD for '\(first.word)' (\(issues.count) pending)")
                self.hudPanel?.show(issue: first, viewModel: viewModel)
            }
        }

        // Dismiss the inline popup immediately when the user types (no 500ms lag).
        // Also dismiss the selection suggestion panel on any keystroke, and cancel
        // any pending external spell-check debounce so the clock resets correctly.
        inputMonitor.onKeystroke = { [weak self] in
            Task { @MainActor in
                // Cancel the spell-check debounce on every keystroke — it will be
                // rescheduled by onWordBoundaryTyped if this was a boundary key.
                self?.externalSpellChecker?.cancel()

                // When the HUD's keyboard monitor is active, it handles all key
                // events itself (including dismissal for non-navigation keys).
                // Don't dismiss here — it would race with the HUD's own handler.
                guard self?.hudPanel?.isAcceptingKeyboardInput != true else {
                    return
                }
                self?.hudPanel?.dismiss()
                self?.selectionPanel?.dismiss()
            }
        }

        // Create the popover
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 320, height: 500)
        pop.behavior = .transient
        pop.animates = true
        pop.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                viewModel: viewModel,
                inputMonitor: inputMonitor
            )
        )
        popover = pop

        // Monitor clicks outside to close popover
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }

        // Register global hotkey (Cmd+Shift+G)
        registerGlobalHotkey()
    }

    public func teardown() {
        badgeObserver?.cancel()
        badgeObserver = nil
        externalSpellChecker?.cancel()
        externalSpellChecker = nil
        selectionMonitor?.stop()
        selectionMonitor = nil
        selectionPanel?.dismiss()
        selectionPanel = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitor = nil
        unregisterGlobalHotkey()
        hudPanel?.dismiss()
        hudPanel = nil
        statusItem = nil
        popover = nil
    }

    // MARK: - Badge

    /// Reactively observe badge-relevant state in DocumentViewModel.
    /// Uses `withObservationTracking` so updates fire immediately when
    /// `totalActiveIssueCount` or `unseenIssueIDs` change — no polling overhead.
    private func startBadgeObserver(viewModel: DocumentViewModel) {
        observeBadgeChanges(viewModel: viewModel)
    }

    private func observeBadgeChanges(viewModel: DocumentViewModel) {
        badgeObserver = Task { @MainActor [weak self] in
            guard let self else { return }
            // Capture current values inside the tracking closure; the onChange
            // callback fires once when any accessed property changes.
            var count = 0
            withObservationTracking {
                count = viewModel.totalActiveIssueCount
                _ = viewModel.unseenIssueIDs.count // track unseenIDs changes too
            } onChange: { [weak self] in
                Task { @MainActor in
                    self?.updateBadge(count: viewModel.totalActiveIssueCount)
                    if viewModel.unseenIssueIDs.count > 0 {
                        self?.animateNewErrors(viewModel: viewModel)
                    }
                    // Re-arm the observation for the next change
                    self?.observeBadgeChanges(viewModel: viewModel)
                }
            }
            // Apply the initial values captured above
            self.updateBadge(count: count)
        }
    }

    private func updateBadge(count: Int) {
        guard let button = statusItem?.button else { return }
        if count > 0 {
            // Draw a composed image: pencil + small red badge with count
            button.image = makeBadgedIcon(count: count)
        } else {
            // Reset to plain template pencil (no badge)
            button.image = plainPencilImage()
        }
    }

    private func plainPencilImage() -> NSImage? {
        let symbolNames = ["pencil.and.sparkles", "pencil.circle.fill", "pencil"]
        for name in symbolNames {
            if let img = NSImage(systemSymbolName: name, accessibilityDescription: "WriteAssist") {
                img.isTemplate = true
                return img
            }
        }
        return nil
    }

    // MARK: - Error Animation

    /// Briefly cycles the status bar icon between the alert icon and the
    /// normal badge to draw the user's attention when new errors appear.
    private func animateNewErrors(viewModel: DocumentViewModel) {
        guard !isAnimating, let button = statusItem?.button else { return }
        isAnimating = true
        let currentImage = button.image

        Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<3 {
                button.image = self.makeAlertIcon()
                try? await Task.sleep(for: .milliseconds(140))
                button.image = currentImage
                try? await Task.sleep(for: .milliseconds(140))
            }
            // Restore the correct badge state after animation
            let count = viewModel.totalActiveIssueCount
            self.updateBadge(count: count)
            self.isAnimating = false
        }
    }

    /// A small orange warning triangle used during the flash animation.
    private func makeAlertIcon() -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        if let img = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                             accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            let tinted = img.withSymbolConfiguration(config) ?? img
            tinted.draw(
                in: NSRect(x: 3, y: 1, width: 16, height: 16),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func makeBadgedIcon(count: Int) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        // Draw base pencil icon (non-template so it renders with actual color)
        if let img = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil) {
            img.isTemplate = false
            img.draw(
                in: NSRect(x: 0, y: 1, width: 14, height: 14),
                from: .zero,
                operation: .sourceOver,
                fraction: 0.85
            )
        }

        // Draw red badge circle
        let badgeRect = NSRect(x: 12, y: 8, width: 10, height: 10)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        // Draw count number
        let label = count > 9 ? "9+" : "\(count)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let strSize = str.size()
        let strOrigin = NSPoint(
            x: badgeRect.midX - strSize.width / 2,
            y: badgeRect.midY - strSize.height / 2
        )
        str.draw(at: strOrigin)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Popover Toggle

    @objc
    func togglePopover() {
        if let pop = popover, pop.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard
            let pop = popover,
            let button = statusItem?.button
        else { return }
        pop.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        // Mark all issues as seen when the popover opens
        viewModel?.markAllSeen()
        // Note: NSApp.activate() is intentionally omitted for .accessory-policy apps.
        // Activating WriteAssist would steal AX focus from the user's text editor,
        // breaking correction injection. .transient popovers attached to status items
        // receive keyboard focus without app activation.
    }

    private func closePopover() {
        popover?.performClose(nil)
    }

    // MARK: - Global Hotkey (Cmd+Shift+G)

    private func registerGlobalHotkey() {
        // Use NSEvent global monitor for key combinations
        // Cmd+Shift+G to toggle the popover
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            // Cmd+Shift+G: keyCode 5 = G
            if flags == [.command, .shift] && event.keyCode == 5 {
                Task { @MainActor in
                    self?.togglePopover()
                }
            }
        }
        logger.info("Global hotkey registered: Cmd+Shift+G")
    }

    private func unregisterGlobalHotkey() {
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        hotkeyMonitor = nil
        logger.debug("Global hotkey unregistered")
    }
}
