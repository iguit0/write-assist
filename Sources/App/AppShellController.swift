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

    // MARK: - Init

    public init(
        selectionImporter: any SelectionImporting = SelectionImportService()
    ) {
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
            onReview: { [weak self] in
                self?.reviewStore.requestReview(trigger: .manualReview)
            }
        )
        let hostingController = NSHostingController(rootView: workbenchView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "WriteAssist"
        window.setContentSize(NSSize(width: 960, height: 640))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.minSize = NSSize(width: 640, height: 440)
        window.center()
        let wc = NSWindowController(window: window)
        reviewWindowController = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Selection import

    /// Imports the current selection from the focused app, opens the review window,
    /// and starts a review automatically. Shows an alert on failure.
    public func reviewSelection() async {
        do {
            let imported = try await selectionImporter.importCurrentSelection()
            openReviewWindow()
            reviewStore.replaceText(
                imported.text,
                source: .importedSelection(imported.metadata),
                trigger: .importedSelection,
                autoReview: true
            )
        } catch let error as SelectionImportError {
            showSelectionImportError(error)
        } catch {
            showSelectionImportError(.noSelection)
        }
    }

    /// Integration point for external callers (URL scheme, XPC) that have already obtained
    /// an `ImportedSelection` and need to route it into the workbench without triggering
    /// the full import flow. For normal "Review Selection" use `reviewSelection()` instead.
    public func applyImportedSelection(_ selection: ImportedSelection) {
        reviewStore.replaceText(
            selection.text,
            source: .importedSelection(selection.metadata),
            trigger: .importedSelection,
            autoReview: true
        )
    }

    // MARK: - Settings

    public func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    // MARK: - Error presentation

    private func showSelectionImportError(_ error: SelectionImportError) {
        let alert = NSAlert()
        alert.messageText = "Cannot Review Selection"
        alert.informativeText = error.userFacingMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
