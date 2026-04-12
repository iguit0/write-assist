// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import SwiftUI
import WriteAssistCore

private final class ReviewSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ReviewSelectionPanelController: NSWindowController, NSWindowDelegate {
    private let panelStore: ReviewSelectionPanelStore
    private let onOpenWorkspace: @MainActor () -> Void
    private let onDismissRequest: @MainActor () -> Void
    private let onAcceptRewrite: @MainActor (String) -> Void
    private let onClose: @MainActor () -> Void

    init(
        panelStore: ReviewSelectionPanelStore,
        onOpenWorkspace: @escaping @MainActor () -> Void,
        onDismissRequest: @escaping @MainActor () -> Void,
        onAcceptRewrite: @escaping @MainActor (String) -> Void,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.panelStore = panelStore
        self.onOpenWorkspace = onOpenWorkspace
        self.onDismissRequest = onDismissRequest
        self.onAcceptRewrite = onAcceptRewrite
        self.onClose = onClose

        let hostingController = NSHostingController(
            rootView: ReviewSelectionPanelView(
                panelStore: panelStore,
                onOpenWorkspace: onOpenWorkspace,
                onAcceptRewrite: onAcceptRewrite,
                onDismiss: onDismissRequest
            )
        )
        let panel = ReviewSelectionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        // Note: .canJoinAllSpaces and .moveToActiveSpace are mutually exclusive.
        panel.collectionBehavior = [.fullScreenAuxiliary, .transient, .ignoresCycle, .moveToActiveSpace]
        panel.tabbingMode = .disallowed
        panel.animationBehavior = .utilityWindow
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(anchorRect: CGRect?) {
        guard let panel = window else { return }
        let origin = resolvedOrigin(anchorRect: anchorRect, size: panel.frame.size)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    func closePanel() {
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    private func resolvedOrigin(anchorRect: CGRect?, size: NSSize) -> NSPoint {
        guard let anchorRect,
              let (screen, convertedRect) = convertedRectForScreen(anchorRect) else {
            return fallbackOrigin(size: size)
        }

        let gap: CGFloat = 12
        let insets: CGFloat = 12
        let visibleFrame = screen.visibleFrame.insetBy(dx: insets, dy: insets)
        let rightOriginX = convertedRect.maxX + gap
        let leftOriginX = convertedRect.minX - gap - size.width
        let originX: CGFloat
        if rightOriginX + size.width <= visibleFrame.maxX {
            originX = rightOriginX
        } else if leftOriginX >= visibleFrame.minX {
            originX = leftOriginX
        } else {
            originX = min(max(visibleFrame.minX, rightOriginX), visibleFrame.maxX - size.width)
        }

        let preferredY = convertedRect.maxY - size.height + 28
        let originY = min(max(visibleFrame.minY, preferredY), visibleFrame.maxY - size.height)
        return NSPoint(x: originX, y: originY)
    }

    private func convertedRectForScreen(_ axRect: CGRect) -> (NSScreen, CGRect)? {
        for screen in NSScreen.screens {
            let converted = CGRect(
                x: axRect.origin.x,
                y: screen.frame.maxY - axRect.maxY,
                width: axRect.width,
                height: axRect.height
            )
            if screen.frame.intersects(converted) {
                return (screen, converted)
            }
        }
        return nil
    }

    private func fallbackOrigin(size: NSSize) -> NSPoint {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return .zero }
        let visibleFrame = screen.visibleFrame
        return NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
    }
}
