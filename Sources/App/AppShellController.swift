// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import Foundation
import SwiftUI
import WriteAssistCore

/// Owns the top-level workbench stores and services.
/// Routes startup, window opening, selection import, and settings.
@MainActor
public final class AppShellController {

    // MARK: - Owned stores and services

    public let reviewStore: ReviewSessionStore
    public let rewriteStore: RewriteSessionStore
    private let selectionImporter: any SelectionImporting
    private var statusBarController: StatusBarController?
    private var reviewWindowController: NSWindowController?

    public private(set) var mode: AppMode

    // MARK: - Init

    public init(
        mode: AppMode = .reviewWorkbenchHybrid,
        selectionImporter: any SelectionImporting = PlaceholderSelectionImportService()
    ) {
        self.mode = mode
        self.reviewStore = ReviewSessionStore()
        self.rewriteStore = RewriteSessionStore()
        self.selectionImporter = selectionImporter
    }

    // MARK: - Lifecycle

    public func start(statusBarController: StatusBarController) {
        self.statusBarController = statusBarController
    }

    public func stop() {
        statusBarController = nil
    }

    // MARK: - Window

    public func openReviewWindow() {
        if let existing = reviewWindowController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let workbenchView = ReviewWorkbenchView(
            reviewStore: reviewStore,
            rewriteStore: rewriteStore,
            onReview: {
                self.reviewStore.requestReview(trigger: .manualReview)
            }
        )
        let hostingController = NSHostingController(rootView: workbenchView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "WriteAssist"
        window.setContentSize(NSSize(width: 900, height: 600))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        let wc = NSWindowController(window: window)
        reviewWindowController = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Selection import

    public func reviewSelection() async {
        do {
            let imported = try await selectionImporter.importCurrentSelection()
            applyImportedSelection(imported)
        } catch {
            // Error handling will be wired in Phase 5 (RW-502)
        }
    }

    public func applyImportedSelection(_ selection: ImportedSelection) {
        let metadata = selection.metadata
        reviewStore.document = ReviewDocument(
            id: reviewStore.document.id,
            text: selection.text,
            source: .importedSelection(metadata),
            revision: reviewStore.document.revision + 1,
            updatedAt: Date()
        )
    }

    // MARK: - Settings

    public func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
