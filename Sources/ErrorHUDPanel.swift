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
    private let keyEventRouter: GlobalKeyEventRouter
    private var panel: NSPanel?

    /// Incremented on each `show()` call so an in-flight async position query
    /// from a previous invocation doesn't present a stale panel.
    private var showGeneration = 0

    /// Timestamp of the last dismiss. Used to enforce a minimum gap between
    /// dismiss and the next show, preventing rapid HUD cycling.
    private var lastDismissTime: ContinuousClock.Instant?

    /// Minimum gap between dismiss and next show.
    private let showCooldown: Duration = .seconds(1.0)

    private var keyboardState: HUDKeyboardState?

    /// Global key event handler token, active only while the HUD panel is visible.
    private var keyHandlerToken: GlobalKeyHandlerToken?

    /// Observer used to dismiss the HUD when the active application changes.
    private var appSwitchObserver: NSObjectProtocol?

    /// Whether the HUD is intercepting keyboard events (panel is shown).
    /// StatusBarController checks this to avoid dismissing on navigation keys.
    private(set) var isAcceptingKeyboardInput = false

    /// Stored callbacks for keyboard-triggered actions.
    private var onApplyCallback: ((String) -> Void)?
    private var onIgnoreCallback: (() -> Void)?
    private var onDismissCallback: (() -> Void)?
    private var onAddToDictionaryCallback: (() -> Void)?
    private var currentSuggestions: [String] = []

    init(keyEventRouter: GlobalKeyEventRouter = .shared) {
        self.keyEventRouter = keyEventRouter
    }

    // MARK: - Public API

    /// Show the inline suggestion popup anchored near the text cursor.
    /// Queries caret bounds via Accessibility on a background thread, then
    /// positions the panel just below the caret. Falls back to the top-right
    /// corner of the screen if the AX query fails.
    func show(issue: WritingIssue, viewModel: DocumentViewModel) {
        // ── Keyboard navigation gate ─────────────────────────────────────────
        // Don't tear down the panel while the user is navigating suggestions
        // with arrow keys. GlobalInputMonitor still calls textDidChange on
        // arrow keys (buffer unchanged), which re-triggers runCheck → show().
        if isAcceptingKeyboardInput {
            logger.debug("show: skipping — keyboard navigation active (\(issue.word))")
            return
        }

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

        logger.info("show: presenting HUD for '\(issue.word, privacy: .sensitive)'")

        // Force-remove any panel including one mid-fade-out animation
        panel?.alphaValue = 0
        panel?.orderOut(nil)
        panel = nil

        showGeneration &+= 1
        let generation = showGeneration

        let addToDictionary: (() -> Void)? = issue.type == .spelling ? { [weak self, weak viewModel] in
            logger.debug("onAddToDictionary: adding '\(issue.word)' to dictionary")
            PersonalDictionary.shared.addWord(issue.word)
            viewModel?.ignoreIssue(issue)
            self?.dismiss()
        } : nil

        let suggestionCount = min(issue.suggestions.count, 4)
        // AI Rewrite is only meaningful for multi-word text (sentences/phrases).
        // Suppress it for single misspelled words — rewriting a bare word produces nonsensical output.
        let isMultiWord = issue.word.split(whereSeparator: \.isWhitespace).count > 1
        let kbState = HUDKeyboardState(suggestionCount: suggestionCount, aiAvailable: CloudAIService.shared.isConfigured && isMultiWord)
        self.keyboardState = kbState

        // Store for keyboard navigation
        currentSuggestions = Array(issue.suggestions.prefix(4))
        onApplyCallback = { [weak self, weak viewModel] suggestion in
            logger.debug("onApply: user selected '\(suggestion, privacy: .sensitive)' for '\(issue.word, privacy: .sensitive)'")
            self?.dismiss()
            viewModel?.applyCorrection(issue, correction: suggestion)
        }
        onIgnoreCallback = { [weak self, weak viewModel] in
            logger.debug("onIgnore: user ignored '\(issue.word, privacy: .sensitive)'")
            // Persist the ignore rule so it survives across sessions (#009).
            // Session-only removal is also applied via ignoreIssue().
            IgnoreRulesStore.shared.addRule(word: issue.word, ruleID: issue.ruleID)
            viewModel?.ignoreIssue(issue)
            self?.dismiss()
        }
        onDismissCallback = { [weak self] in
            logger.debug("onDismiss: user dismissed HUD")
            self?.dismiss()
        }
        onAddToDictionaryCallback = addToDictionary

        let contentView = InlineSuggestionView(
            issue: issue,
            onApply: { [weak self] suggestion in self?.onApplyCallback?(suggestion) },
            onIgnore: { [weak self] in self?.onIgnoreCallback?() },
            onDismiss: { [weak self] in self?.onDismissCallback?() },
            onAddToDictionary: addToDictionary,
            keyboardState: kbState
        )

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
            self.installKeyMonitor()
            self.installAppSwitchObserver()
        }
    }

    // MARK: - Keyboard Navigation

    private func installKeyMonitor() {
        removeKeyMonitor()
        isAcceptingKeyboardInput = true

        keyHandlerToken = keyEventRouter.register(priority: 250) { [weak self] event in
            self?.handleKeyEvent(event) ?? false
        }
        logger.debug("installKeyMonitor: keyboard navigation active")
    }

    private func removeKeyMonitor() {
        if let keyHandlerToken {
            keyEventRouter.unregister(keyHandlerToken)
        }
        keyHandlerToken = nil
        isAcceptingKeyboardInput = false
    }

    private func installAppSwitchObserver() {
        removeAppSwitchObserver()
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    private func removeAppSwitchObserver() {
        if let observer = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appSwitchObserver = nil
        }
    }

    private func handleKeyEvent(_ event: GlobalKeyEvent) -> Bool {
        let modifiers = event.modifiers.intersection([.command, .control, .option])
        guard modifiers.isEmpty else {
            logger.debug("handleKeyEvent: modifier shortcut — dismissing")
            dismiss()
            return false
        }

        let keyCode = event.keyCode

        switch keyCode {
        case 125: // Down Arrow
            keyboardState?.moveDown()
            logger.debug("handleKeyEvent: ↓ — selectedIndex=\(self.keyboardState?.selectedIndex ?? -1)")
            return true

        case 126: // Up Arrow
            keyboardState?.moveUp()
            logger.debug("handleKeyEvent: ↑ — selectedIndex=\(self.keyboardState?.selectedIndex ?? -1)")
            return true

        case 36, 76: // Return / Enter
            if let kbs = keyboardState {
                if kbs.isAIRewriteSelected {
                    if let result = kbs.rewriteResult {
                        logger.debug("handleKeyEvent: ↵ — applying AI rewrite")
                        onApplyCallback?(result)
                    } else {
                        logger.debug("handleKeyEvent: ↵ — triggering AI rewrite")
                        kbs.triggerRewrite?()
                    }
                } else if let index = kbs.selectedIndex, index < currentSuggestions.count {
                    let suggestion = currentSuggestions[index]
                    logger.debug("handleKeyEvent: ↵ — applying '\(suggestion, privacy: .sensitive)'")
                    onApplyCallback?(suggestion)
                }
            }
            return true

        case 53: // Escape
            logger.debug("handleKeyEvent: esc — dismissing")
            onDismissCallback?()
            return true

        default:
            // Check for character shortcuts
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                case "r":
                    // 'r' is a direct shortcut to trigger or apply the AI rewrite.
                    if let kbs = keyboardState, kbs.aiAvailable {
                        if let result = kbs.rewriteResult {
                            logger.debug("handleKeyEvent: 'r' — applying AI rewrite")
                            onApplyCallback?(result)
                        } else {
                            logger.debug("handleKeyEvent: 'r' — triggering AI rewrite")
                            kbs.triggerRewrite?()
                        }
                        return true
                    }
                    dismiss()
                    return false
                case "i":
                    logger.debug("handleKeyEvent: 'i' — ignoring issue")
                    onIgnoreCallback?()
                    return true
                case "d":
                    if onAddToDictionaryCallback != nil {
                        logger.debug("handleKeyEvent: 'd' — adding to dictionary")
                        onAddToDictionaryCallback?()
                        return true
                    }
                    dismiss()
                    return false
                default:
                    dismiss()
                    return false
                }
            }
            return false
        }
    }

    /// Fade out and remove the HUD panel.
    func dismiss() {
        removeKeyMonitor()
        removeAppSwitchObserver()
        onApplyCallback = nil
        onIgnoreCallback = nil
        onDismissCallback = nil
        onAddToDictionaryCallback = nil
        currentSuggestions = []
        keyboardState = nil
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
    /// Delegates to `PanelPositioning.origin(caretBounds:panelSize:gap:)` (#021).
    private static func caretAnchoredOrigin(caretBounds: CGRect, hudSize: NSSize) -> NSPoint {
        PanelPositioning.origin(caretBounds: caretBounds, panelSize: hudSize)
    }

    /// Delegates to `PanelPositioning.topRightFallback(panelSize:)` (#021).
    private static func topRightFallbackOrigin(hudSize: NSSize) -> NSPoint {
        PanelPositioning.topRightFallback(panelSize: hudSize)
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
    /// caret in the currently focused UI element. Delegates to `AXHelper` (#020).
    private nonisolated static func queryCaretBounds() -> CGRect? {
        guard let element = AXHelper.focusedElement() else {
            logger.debug("queryCaretBounds: no focused element")
            return nil
        }
        guard let rangeRef = AXHelper.selectedRangeRef(of: element) else {
            logger.debug("queryCaretBounds: no selected text range")
            return nil
        }
        guard let rect = AXHelper.bounds(for: rangeRef, in: element) else {
            logger.debug("queryCaretBounds: no bounds for range")
            return nil
        }
        return rect
    }
}

// MARK: - Keyboard Navigation State

/// Shared state between ErrorHUDPanel (key monitor) and InlineSuggestionView
/// (rendering). ErrorHUDPanel mutates; InlineSuggestionView observes.
@MainActor
@Observable
final class HUDKeyboardState {
    var selectedIndex: Int?
    let suggestionCount: Int

    /// Whether the AI Rewrite slot is available (AI is configured).
    let aiAvailable: Bool

    /// Set by InlineSuggestionView on appear so the key handler can trigger
    /// a rewrite without holding a direct reference to the view.
    var triggerRewrite: (() -> Void)?

    /// Updated by InlineSuggestionView when the AI response arrives.
    /// Shared here so ErrorHUDPanel.handleKeyEvent can apply it on Enter.
    var rewriteResult: String?

    /// Set when `performAIRewrite()` fails. Auto-clears after 3 s so the
    /// button returns to its idle state without requiring user action.
    var rewriteError: String?

    /// Total navigable slots: suggestions + optional AI Rewrite row.
    var totalSlotCount: Int { suggestionCount + (aiAvailable ? 1 : 0) }

    /// True when the cursor has moved into the AI Rewrite slot.
    var isAIRewriteSelected: Bool {
        guard aiAvailable, let idx = selectedIndex else { return false }
        return idx == suggestionCount
    }

    init(suggestionCount: Int, aiAvailable: Bool) {
        self.suggestionCount = suggestionCount
        self.aiAvailable = aiAvailable
    }

    func moveDown() {
        guard totalSlotCount > 0 else { return }
        if let current = selectedIndex {
            selectedIndex = (current + 1) % totalSlotCount
        } else {
            selectedIndex = 0
        }
    }

    func moveUp() {
        guard totalSlotCount > 0 else { return }
        if let current = selectedIndex {
            selectedIndex = (current - 1 + totalSlotCount) % totalSlotCount
        } else {
            selectedIndex = totalSlotCount - 1
        }
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
    let onAddToDictionary: (() -> Void)?
    var keyboardState: HUDKeyboardState

    @State private var hoveredSuggestion: String?
    @State private var isRewriting = false
    // `rewriteResult` lives in keyboardState so ErrorHUDPanel.handleKeyEvent can apply it.

    private var accentColor: Color {
        issue.type.color
    }

    /// Pre-capped suggestion list — avoids repeated Array allocation inside body.
    private var cappedSuggestions: [String] {
        Array(issue.suggestions.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider().padding(.horizontal, 8)
            wordDisplayView
            suggestionsListView
            aiRewriteView
            Divider().padding(.horizontal, 8).padding(.top, 4)
            actionButtonsView
            keyboardHintBar
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(issue.type.categoryLabel) issue: \(issue.message)")
        .accessibilityHint(accessibilityShortcutHint)
        .onAppear {
            // Register the AI rewrite trigger so ErrorHUDPanel.handleKeyEvent
            // can fire it via keyboard without a direct reference to this view.
            keyboardState.triggerRewrite = { performAIRewrite() }
            // Announce the HUD to VoiceOver users (#034).
            if let app = NSApp {
                NSAccessibility.post(
                    element: app,
                    notification: .announcementRequested,
                    userInfo: [
                        NSAccessibility.NotificationUserInfoKey.announcement:
                            "\(issue.type.categoryLabel): \(issue.message)",
                        NSAccessibility.NotificationUserInfoKey.priority:
                            NSAccessibilityPriorityLevel.high.rawValue
                    ]
                )
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 3, height: 14)
            Image(systemName: issue.type.icon)
                .font(.system(size: 10))
                .foregroundStyle(accentColor)
            Text(issue.type.categoryLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accentColor)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(issue.message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(4)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss suggestion")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var wordDisplayView: some View {
        Text("\"\(issue.word)\"")
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.top, 8)
    }

    @ViewBuilder
    private var suggestionsListView: some View {
        if issue.suggestions.isEmpty {
            Text("No suggestions available")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(cappedSuggestions.enumerated()), id: \.offset) { index, suggestion in
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
                    .accessibilityLabel("Apply correction: \(suggestion)")
                    .accessibilityValue(keyboardState.selectedIndex == index ? "Selected" : "")
                    .accessibilityHint(keyboardState.selectedIndex == index ? "Press Return to apply" : "")
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(
                                suggestionOpacity(for: suggestion, at: index)
                            ))
                    )
                    .animation(.easeInOut(duration: 0.15), value: hoveredSuggestion)
                    .animation(.easeInOut(duration: 0.1), value: keyboardState.selectedIndex)
                    .onHover { isHovered in
                        hoveredSuggestion = isHovered ? suggestion : nil
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var aiRewriteView: some View {
        if keyboardState.aiAvailable {
            Divider().padding(.horizontal, 8).padding(.top, 4)

            if let rewrite = keyboardState.rewriteResult {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundStyle(.indigo)
                    Text("AI:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.indigo)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)

                Button {
                    onApply(rewrite)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.indigo)
                            .frame(width: 12)
                        Text(rewrite)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apply AI rewrite")
                .accessibilityValue(keyboardState.isAIRewriteSelected ? "Selected" : "")
                .accessibilityHint(keyboardState.isAIRewriteSelected ? "Press Return to apply" : "")
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(keyboardState.isAIRewriteSelected ? 0.12 : 0.0))
                )
                .animation(.easeInOut(duration: 0.1), value: keyboardState.isAIRewriteSelected)
            } else if isRewriting {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Rewriting...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } else if let errorMsg = keyboardState.rewriteError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 9))
                    Text(errorMsg)
                        .font(.system(size: 10))
                    Spacer()
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .animation(.easeInOut(duration: 0.2), value: errorMsg)
            } else {
                Button {
                    performAIRewrite()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                        Text("AI Rewrite")
                            .font(.system(size: 10))
                        Spacer()
                    }
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("AI rewrite")
                .accessibilityValue(keyboardState.isAIRewriteSelected ? "Selected" : "")
                .accessibilityHint(keyboardState.isAIRewriteSelected ? "Press Return to rewrite" : "")
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(keyboardState.isAIRewriteSelected ? 0.12 : 0.0))
                )
                .animation(.easeInOut(duration: 0.1), value: keyboardState.isAIRewriteSelected)
            }
        }
    }

    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            if let onAddToDictionary, issue.type == .spelling {
                Button(action: onAddToDictionary) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 10))
                        Text("Add to Dictionary")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.blue)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(issue.word) to personal dictionary")
            }

            Spacer()

            Button(action: onIgnore) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10))
                    Text("Ignore")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ignore this \(issue.type.categoryLabel.lowercased()) issue")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var keyboardHintBar: some View {
        Text(keyboardShortcutSummary)
            .font(.system(size: 9))
            .foregroundStyle(.quaternary)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Keyboard shortcuts: \(accessibilityShortcutHint)")
    }

    private var keyboardShortcutSummary: String {
        var parts = ["↑↓ navigate", "↵ apply", "i ignore", "esc dismiss"]
        if issue.type == .spelling {
            parts.append("d add to dict")
        }
        if keyboardState.aiAvailable {
            parts.append("r rewrite")
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityShortcutHint: String {
        var parts = [
            "Use up and down arrow keys to navigate suggestions",
            "press Return to apply",
            "press I to ignore",
            "press Escape to dismiss"
        ]
        if issue.type == .spelling {
            parts.append("press D to add the word to the dictionary")
        }
        if keyboardState.aiAvailable {
            parts.append("press R to trigger the AI rewrite")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Helpers

    private func suggestionOpacity(for suggestion: String, at index: Int) -> Double {
        if keyboardState.selectedIndex == index {
            return 0.12
        } else if hoveredSuggestion == suggestion {
            return 0.07
        }
        return 0.0
    }

    private func performAIRewrite() {
        isRewriting = true
        keyboardState.rewriteError = nil
        Task {
            do {
                let result = try await CloudAIService.shared.rewrite(
                    text: issue.word, style: .clearer
                )
                keyboardState.rewriteResult = result
            } catch is CancellationError {
                // Task was cancelled (HUD dismissed mid-flight) — no user action needed.
            } catch {
                // Surface a brief error so the user knows why the rewrite didn't appear.
                keyboardState.rewriteError = "AI unavailable — try again"
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    keyboardState.rewriteError = nil
                }
            }
            isRewriting = false
        }
    }
}
