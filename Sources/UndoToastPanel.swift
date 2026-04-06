// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.
// LEGACY — Non-primary. Part of the ambient inline-monitor path superseded by the Review
// Workbench. No new product behavior should be added here.

import AppKit
import os
import SwiftUI

private let logger = Logger(subsystem: "com.writeassist", category: "UndoToastPanel")

/// Small floating toast that appears near the caret after a correction is applied,
/// offering a short window to undo the change.
@MainActor
final class UndoToastPanel {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var showGeneration = 0
    private var appSwitchObserver: NSObjectProtocol?

    func show(original: String, correction: String, onUndo: @escaping () -> Void) {
        dismiss()
        showGeneration &+= 1
        let generation = showGeneration

        let contentView = UndoToastView(
            original: original,
            correction: correction,
            onUndo: onUndo
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 280, height: 60))
        hostingView.layout()
        let fittingSize = hostingView.fittingSize
        let panelSize = NSSize(
            width: max(fittingSize.width, 240),
            height: max(fittingSize.height, 44)
        )

        Task { @MainActor [weak self] in
            guard let self, self.showGeneration == generation else { return }
            let caretBounds = await Self.queryCaretBoundsAsync()
            let origin = caretBounds.map {
                PanelPositioning.origin(caretBounds: $0, panelSize: panelSize, gap: 6)
            } ?? PanelPositioning.topRightFallback(panelSize: panelSize)
            self.presentPanel(hostingView: hostingView, size: panelSize, origin: origin)
            self.installAppSwitchObserver()
            self.scheduleAutoDismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        removeAppSwitchObserver()
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in p.orderOut(nil) }
        })
    }

    private func scheduleAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            logger.debug("auto-dismiss")
            self?.dismiss()
        }
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
        p.hasShadow = false
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

        NSAccessibility.post(
            element: hostingView,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement:
                    "Correction applied. Undo is available.",
                NSAccessibility.NotificationUserInfoKey.priority:
                    NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    private func installAppSwitchObserver() {
        removeAppSwitchObserver()
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
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

    private static func queryCaretBoundsAsync() async -> CGRect? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                continuation.resume(returning: AXHelper.caretBounds())
            }
        }
    }
}

private struct UndoToastView: View {
    let original: String
    let correction: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)

            Text("\"\(original)\" → \"\(correction)\"")
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Button("Undo") {
                onUndo()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Undo correction")
            .accessibilityHint("Replaces \(correction) with \(original)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                )
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Correction applied")
        .accessibilityValue("\(original) to \(correction)")
        .accessibilityHint("Activate Undo to revert the change")
    }
}
