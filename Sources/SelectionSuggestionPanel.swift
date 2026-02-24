// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import os
import SwiftUI

private let logger = Logger(subsystem: "com.writeassist", category: "SelectionSuggestionPanel")

// MARK: - Suggestion Tab

/// Rewrite styles offered in the selection suggestion popup.
enum SuggestionTab: String, CaseIterable, Hashable {
    case improve = "Improve"
    case rephrase = "Rephrase"
    case shorten = "Shorten"
    case formal = "Formal"
    case friendly = "Friendly"

    var label: String { rawValue }

    var rewriteStyle: AIRewriteStyle {
        switch self {
        case .improve: return .clearer
        case .rephrase: return .rephrase
        case .shorten: return .concise
        case .formal: return .formal
        case .friendly: return .friendly
        }
    }

    var loadingLabel: String {
        switch self {
        case .improve: return "Improving…"
        case .rephrase: return "Rephrasing…"
        case .shorten: return "Shortening…"
        case .formal: return "Making formal…"
        case .friendly: return "Making friendly…"
        }
    }

    var descriptionLabel: String {
        switch self {
        case .improve: return "Fix grammar and clarity."
        case .rephrase: return "Same meaning, fresh expression."
        case .shorten: return "Remove unnecessary words."
        case .formal: return "Use professional language."
        case .friendly: return "Use a warm, casual tone."
        }
    }
}

// MARK: - Selection Suggestion State

/// Observable state shared between `SelectionSuggestionPanel` (writes)
/// and `SelectionSuggestionView` (reads).
@MainActor
@Observable
final class SelectionSuggestionState {
    var selectedText: String = ""
    var activeTab: SuggestionTab = .improve
    var tabResults: [SuggestionTab: String] = [:]
    /// Tabs currently waiting for an AI response.
    var loadingTabs: Set<SuggestionTab> = []
    var errorMessage: String?

    /// Resets all state for a fresh selection.
    func reset(for text: String) {
        selectedText = text
        activeTab = .improve
        tabResults = [:]
        loadingTabs = []
        errorMessage = nil
    }
}

// MARK: - Selection Suggestion Panel

/// A non-activating floating `NSPanel` that appears near the user's text selection
/// in any application and offers Grammarly-style AI rewriting tabs.
///
/// Mirrors the `ErrorHUDPanel` architecture:
/// - `.nonactivatingPanel` so the original app keeps focus + selection
/// - AX-based positioning near the selection bounds
/// - `showGeneration` + `showCooldown` guards prevent rapid cycling
/// - SwiftUI content hosted via `NSHostingView`
@MainActor
final class SelectionSuggestionPanel {

    private var panel: NSPanel?
    private var hostingView: NSView?
    private var state: SelectionSuggestionState?
    /// Per-tab loading tasks — prevents cancelling background tabs on switch.
    private var loadingTasks: [SuggestionTab: Task<Void, Never>] = [:]
    private var keyMonitor: Any?
    private var appSwitchObserver: NSObjectProtocol?
    private var showGeneration = 0
    private var lastDismissTime: ContinuousClock.Instant?
    private let showCooldown: Duration = .seconds(1.0)

    private weak var viewModel: DocumentViewModel?

    // MARK: - Init

    init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Public API

    /// `true` while the panel is on screen.
    var isVisible: Bool { panel != nil }

    /// Show the panel near `caretBounds`, loading the Improve tab suggestion immediately.
    func show(selectedText: String, range: NSRange, near caretBounds: CGRect) {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let lastDismiss = lastDismissTime,
           ContinuousClock.now - lastDismiss < showCooldown {
            logger.debug("show: skipping — within cooldown")
            return
        }

        logger.info("show: '\(trimmed.prefix(40))'")

        // Tear down any existing panel immediately (no fade — we're replacing it).
        panel?.alphaValue = 0
        panel?.orderOut(nil)
        panel = nil
        removeKeyMonitor()
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks = [:]

        showGeneration &+= 1
        let generation = showGeneration

        let panelState = SelectionSuggestionState()
        panelState.reset(for: trimmed)
        state = panelState

        let hostingView = buildHostingView(state: panelState)
        // With fixedSize(horizontal:vertical:) on the SwiftUI view, fittingSize reliably
        // returns the intrinsic content height. A single layout() pass is enough to
        // initialise the view before the panel is presented.
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 400, height: 0))
        hostingView.layout()
        let fitting = hostingView.fittingSize
        let panelSize = NSSize(width: max(fitting.width, 400), height: max(fitting.height, 180))

        Task { @MainActor [weak self] in
            guard let self, showGeneration == generation else { return }

            let origin: NSPoint
            if caretBounds != .zero {
                origin = Self.caretAnchoredOrigin(caretBounds: caretBounds, panelSize: panelSize)
            } else {
                // Fallback: query caret bounds asynchronously.
                let asyncBounds = await Self.queryCaretBoundsAsync()
                guard showGeneration == generation else { return }
                origin = asyncBounds.map {
                    Self.caretAnchoredOrigin(caretBounds: $0, panelSize: panelSize)
                } ?? Self.topRightFallbackOrigin(panelSize: panelSize)
            }

            presentPanel(hostingView: hostingView, size: panelSize, origin: origin)
            // Auto-load the first tab so content appears immediately.
            loadTab(.improve, state: panelState)
        }
    }

    /// Fade out and remove the panel.
    func dismiss() {
        removeKeyMonitor()
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks = [:]
        state = nil
        hostingView = nil
        if let obs = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appSwitchObserver = nil
        }
        guard let p = panel else { return }
        panel = nil
        lastDismissTime = .now
        logger.debug("dismiss: fading out")
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            p.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in p.orderOut(nil) }
        })
    }

    /// Switch to a different tab, loading its suggestion lazily if needed.
    func switchTab(_ tab: SuggestionTab) {
        guard let panelState = state else { return }
        panelState.activeTab = tab
        if panelState.tabResults[tab] == nil, loadingTasks[tab] == nil {
            loadTab(tab, state: panelState)
        }
    }

    /// Apply the current tab's suggestion to the focused application.
    func applyCurrentSuggestion() {
        guard let panelState = state,
              let result = panelState.tabResults[panelState.activeTab],
              let vm = viewModel else { return }
        let replacement = result
        dismiss()
        vm.replaceSelection(replacement: replacement)
    }

    // MARK: - Private

    private func loadTab(_ tab: SuggestionTab, state: SelectionSuggestionState) {
        guard CloudAIService.shared.isConfigured else {
            state.errorMessage = "Add an API key in Settings to use AI suggestions."
            return
        }
        guard loadingTasks[tab] == nil else { return }  // already loading
        let text = state.selectedText
        state.loadingTabs.insert(tab)
        state.errorMessage = nil

        let task = Task { @MainActor [weak self] in
            defer {
                self?.loadingTasks[tab] = nil
            }
            do {
                let result = try await CloudAIService.shared.rewrite(
                    text: text, style: tab.rewriteStyle
                )
                guard !Task.isCancelled else {
                    state.loadingTabs.remove(tab)
                    return
                }
                state.tabResults[tab] = result
                state.loadingTabs.remove(tab)
                self?.resizePanelIfNeeded()
            } catch is CancellationError {
                state.loadingTabs.remove(tab)
            } catch {
                guard !Task.isCancelled else {
                    state.loadingTabs.remove(tab)
                    return
                }
                state.loadingTabs.remove(tab)
                // Only surface the error if this was the visible tab
                if state.activeTab == tab {
                    state.errorMessage = "Generation failed — try again."
                }
                logger.warning("loadTab \(tab.rawValue): \(error.localizedDescription)")
            }
        }
        loadingTasks[tab] = task
    }

    private func resizePanelIfNeeded() {
        guard let hv = hostingView, let p = panel else { return }
        // With fixedSize on the SwiftUI view, fittingSize returns the true intrinsic
        // content height without pre-setting the frame to a large measurement size.
        // Pre-setting the frame to 400pt was causing the layout to expand and
        // return inflated (or zero, for NSScrollView-backed Text) heights.
        let fitting = hv.fittingSize
        let newSize = NSSize(width: max(fitting.width, 400), height: max(fitting.height, 180))
        guard abs(newSize.height - p.frame.height) > 4 else { return }  // avoid micro-resizes
        // Keep the top-left corner anchored while resizing vertically.
        var frame = p.frame
        let delta = newSize.height - frame.height
        frame.origin.y -= delta
        frame.size = newSize
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().setFrame(frame, display: true)
        }
    }

    private func buildHostingView(state: SelectionSuggestionState) -> NSView {
        let contentView = SelectionSuggestionView(
            state: state,
            onAccept: { [weak self] in self?.applyCurrentSuggestion() },
            onDismiss: { [weak self] in self?.dismiss() },
            onTabSelected: { [weak self] tab in self?.switchTab(tab) }
        )
        let hv = NSHostingView(rootView: contentView)
        hostingView = hv
        return hv
    }

    private func presentPanel(hostingView: NSView, size: NSSize, origin: NSPoint) {
        let p = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false         // SelectionSuggestionView applies its own SwiftUI shadow
        p.contentView = hostingView
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.alphaValue = 0

        panel = p
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 1
        }

        installKeyMonitor()
        installAppSwitchObserver()
    }

    // MARK: - Keyboard Monitor

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                let modifiers = event.modifierFlags.intersection([.command, .control, .option])
                guard modifiers.isEmpty else { return }
                switch event.keyCode {
                case 53: // Escape
                    self?.dismiss()
                case 36, 76: // Return / Enter
                    self?.applyCurrentSuggestion()
                default:
                    break
                }
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - App-Switch Observer

    private func installAppSwitchObserver() {
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

    // MARK: - Positioning (mirrors ErrorHUDPanel)

    private static func caretAnchoredOrigin(caretBounds: CGRect, panelSize: NSSize) -> NSPoint {
        // AX uses top-left origin; AppKit uses bottom-left origin.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900

        let caretTopAppKit = primaryHeight - caretBounds.minY
        let caretBottomAppKit = primaryHeight - caretBounds.maxY
        let caretX = caretBounds.origin.x

        let caretCenter = NSPoint(
            x: caretX + caretBounds.width / 2,
            y: (caretTopAppKit + caretBottomAppKit) / 2
        )
        let screen = NSScreen.screens.first { $0.frame.contains(caretCenter) }
        let visibleFrame = screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let gap: CGFloat = 6

        var y = caretBottomAppKit - gap - panelSize.height
        if y < visibleFrame.minY {
            y = caretTopAppKit + gap
        }

        var x = caretX
        x = max(visibleFrame.minX + 8, min(x, visibleFrame.maxX - panelSize.width - 8))
        y = max(visibleFrame.minY, min(y, visibleFrame.maxY - panelSize.height))

        return NSPoint(x: x, y: y)
    }

    private static func topRightFallbackOrigin(panelSize: NSSize) -> NSPoint {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(
            x: frame.maxX - panelSize.width - 16,
            y: frame.maxY - panelSize.height - 8
        )
    }

    private static func queryCaretBoundsAsync() async -> CGRect? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                continuation.resume(returning: queryCaretBoundsSync())
            }
        }
    }

    private nonisolated static func queryCaretBoundsSync() -> CGRect? {
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

        let element = focusedRef as! AXUIElement

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeRef else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef,
            &boundsRef
        ) == .success, let boundsRef else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }
}
