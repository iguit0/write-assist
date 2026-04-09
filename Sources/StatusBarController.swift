// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import os
import SwiftUI

private let logger = Logger(subsystem: "com.writeassist", category: "StatusBarController")

/// Manages the macOS menu bar status item in launcher-only mode.
/// Exposes three actions: Open Review, Review Selection, and Settings.
/// No popover, no ambient monitors, no floating panels.
@MainActor
public final class StatusBarController: NSObject, @unchecked Sendable {

    private var statusItem: NSStatusItem?
    private var launcherMenuHandlers: [MenuActionHandler] = []

    public override init() {
        super.init()
    }

    /// Creates the status item with a plain NSMenu.
    public func setupLauncher(
        onOpenReview: @escaping @MainActor () -> Void,
        onReviewSelection: @escaping @MainActor () -> Void,
        onOpenSettings: @escaping @MainActor () -> Void
    ) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.wantsLayer = true
            if let img = resolvedStatusBarIcon() {
                button.image = img
            } else {
                button.title = "✏️"
            }
        }
        statusItem = item

        let menu = NSMenu()

        let openReviewHandler = MenuActionHandler(action: onOpenReview)
        let openReviewItem = NSMenuItem(
            title: "Open Review",
            action: #selector(MenuActionHandler.handleAction),
            keyEquivalent: ""
        )
        openReviewItem.target = openReviewHandler
        menu.addItem(openReviewItem)

        menu.addItem(.separator())

        let reviewSelectionHandler = MenuActionHandler(action: onReviewSelection)
        let reviewSelectionItem = NSMenuItem(
            title: "Review Selection",
            action: #selector(MenuActionHandler.handleAction),
            keyEquivalent: ""
        )
        reviewSelectionItem.target = reviewSelectionHandler
        menu.addItem(reviewSelectionItem)

        menu.addItem(.separator())

        let openSettingsHandler = MenuActionHandler(action: onOpenSettings)
        let openSettingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(MenuActionHandler.handleAction),
            keyEquivalent: ""
        )
        openSettingsItem.target = openSettingsHandler
        menu.addItem(openSettingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit WriteAssist",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        item.menu = menu

        // Retain handlers for the lifetime of the menu
        launcherMenuHandlers = [openReviewHandler, reviewSelectionHandler, openSettingsHandler]

        logger.info("StatusBarController: launcher mode active")
    }

    public func teardown() {
        statusItem = nil
        launcherMenuHandlers = []
    }

    // MARK: - Icon

    /// Resolves the status bar pencil icon by trying SF Symbol names in order of
    /// availability. Returns nil only when no symbols resolve (rare in production).
    private func resolvedStatusBarIcon() -> NSImage? {
        let symbolNames = ["pencil.and.sparkles", "pencil.circle.fill", "pencil"]
        for name in symbolNames {
            if let img = NSImage(systemSymbolName: name, accessibilityDescription: "WriteAssist") {
                img.isTemplate = true
                return img
            }
        }
        return nil
    }
}

// MARK: - MenuActionHandler

/// Trampoline target that bridges an NSMenuItem action to a `@MainActor` closure.
/// Instances must be retained for as long as their menu item is live.
private final class MenuActionHandler: NSObject {
    let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc @MainActor func handleAction() {
        let closure = action
        Task { @MainActor in
            closure()
        }
    }
}
