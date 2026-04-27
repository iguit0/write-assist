// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import WriteAssistCore

/// Owns the top-level workbench stores and services.
/// Routes startup, panel/window presentation, selection import, and settings.
@MainActor
public final class AppShellController {

    // MARK: - Owned stores and services

    public let reviewStore: ReviewSessionStore
    public let rewriteStore: RewriteSessionStore
    private let selectionReviewStore: ReviewSessionStore
    private let reviewSelectionPanelStore: ReviewSelectionPanelStore
    private let selectionImporter: any SelectionImporting
    private var statusBarController: StatusBarController?
    private var reviewWindowController: NSWindowController?
    private var reviewSelectionPanelController: ReviewSelectionPanelController?
    private var settingsWindowController: NSWindowController?
    private var aboutWindowController: NSWindowController?
    private var reviewSelectionTask: Task<Void, Never>?
    private var reviewSelectionGeneration = 0
    private let panelRewriteStore: RewriteSessionStore

    // MARK: - Init

    public init(
        selectionImporter: any SelectionImporting = SelectionImportService()
    ) {
        let reviewStore = ReviewSessionStore()
        let rewriteStore = RewriteSessionStore()
        let selectionReviewStore = ReviewSessionStore()

        self.reviewStore = reviewStore
        self.rewriteStore = rewriteStore
        self.selectionReviewStore = selectionReviewStore
        let panelRewriteStore = RewriteSessionStore()
        self.panelRewriteStore = panelRewriteStore
        self.reviewSelectionPanelStore = ReviewSelectionPanelStore(reviewStore: selectionReviewStore, rewriteStore: panelRewriteStore)
        self.selectionImporter = selectionImporter
    }

    // MARK: - Lifecycle

    public func start(statusBarController: StatusBarController) {
        self.statusBarController = statusBarController
    }

    public func stop() {
        reviewSelectionGeneration += 1
        reviewSelectionTask?.cancel()
        reviewSelectionTask = nil
        selectionReviewStore.cancelReview()
        reviewSelectionPanelStore.reset()
        reviewSelectionPanelController?.closePanel()
        reviewSelectionPanelController = nil
        statusBarController = nil
        settingsWindowController = nil
    }

    // MARK: - Workspace window

    public func openWorkspaceWindow() {
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

        let controller = NSWindowController(window: window)
        reviewWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Selection review panel

    public func triggerReviewSelection() {
        reviewSelectionTask?.cancel()
        reviewSelectionGeneration += 1
        let generation = reviewSelectionGeneration
        let anchorRect = AXHelper.selectedTextBounds(skipSelf: true)

        reviewSelectionPanelStore.beginImport()
        ensureReviewSelectionPanel().show(anchorRect: anchorRect)

        reviewSelectionTask = Task { @MainActor [weak self] in
            defer {
                if let self, generation == self.reviewSelectionGeneration {
                    self.reviewSelectionTask = nil
                }
            }
            await self?.reviewSelection(generation: generation)
        }
    }

    public func reviewSelection() async {
        reviewSelectionGeneration += 1
        let generation = reviewSelectionGeneration
        reviewSelectionPanelStore.beginImport()
        ensureReviewSelectionPanel().show(anchorRect: AXHelper.selectedTextBounds(skipSelf: true))
        await reviewSelection(generation: generation)
    }

    private func reviewSelection(generation: Int) async {
        do {
            let imported = try await selectionImporter.importCurrentSelection()
            guard !Task.isCancelled,
                  generation == reviewSelectionGeneration else { return }

            reviewSelectionPanelStore.showImportedSelection(imported)
            selectionReviewStore.replaceText(
                imported.text,
                source: .importedSelection(imported.metadata),
                trigger: .importedSelection,
                autoReview: true
            )
        } catch let error as SelectionImportError {
            guard !Task.isCancelled,
                  generation == reviewSelectionGeneration else { return }
            reviewSelectionPanelStore.showImportError(error)
        } catch {
            guard !Task.isCancelled,
                  generation == reviewSelectionGeneration else { return }
            reviewSelectionPanelStore.showImportError(.noSelection)
        }
    }

    /// Integration point for external callers (URL scheme, XPC) that have already obtained
    /// an `ImportedSelection` and need to route it into the workbench without triggering
    /// the panel import flow.
    public func applyImportedSelection(_ selection: ImportedSelection) {
        loadImportedSelectionIntoWorkspace(selection)
    }

    private func loadImportedSelectionIntoWorkspace(_ selection: ImportedSelection) {
        rewriteStore.rejectCandidates()
        reviewStore.replaceText(
            selection.text,
            source: .importedSelection(selection.metadata),
            trigger: .importedSelection,
            autoReview: true
        )
    }

    private func openWorkspaceFromReviewPanel() {
        if let importedSelection = reviewSelectionPanelStore.importedSelection {
            loadImportedSelectionIntoWorkspace(importedSelection)
        }
        openWorkspaceWindow()
        dismissReviewSelectionPanel()
    }

    private func dismissReviewSelectionPanel() {
        reviewSelectionGeneration += 1
        reviewSelectionTask?.cancel()
        reviewSelectionTask = nil
        reviewSelectionPanelStore.reset()
        reviewSelectionPanelController?.closePanel()
    }

    private func handleReviewSelectionPanelClosed() {
        reviewSelectionGeneration += 1
        reviewSelectionTask?.cancel()
        reviewSelectionTask = nil
        reviewSelectionPanelStore.reset()
    }

    private func handleAcceptRewrite(_ text: String) {
        // 1. Close panel first so source app regains focus
        reviewSelectionPanelController?.closePanel()

        // 2. Write to pasteboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // 3. Simulate Cmd+V after a brief delay to let focus settle
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            Self.simulatePaste()
        }

        // 4. Reset panel state
        reviewSelectionPanelStore.reset()
    }

    private static func simulatePaste() {
        // 0x09 = 'v' virtual key code; nil source = synthesized HID event
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = CGEventFlags.maskCommand
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = CGEventFlags.maskCommand
        keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private func ensureReviewSelectionPanel() -> ReviewSelectionPanelController {
        if let reviewSelectionPanelController {
            return reviewSelectionPanelController
        }

        let controller = ReviewSelectionPanelController(
            panelStore: reviewSelectionPanelStore,
            onOpenWorkspace: { [weak self] in
                self?.openWorkspaceFromReviewPanel()
            },
            onDismissRequest: { [weak self] in
                self?.dismissReviewSelectionPanel()
            },
            onAcceptRewrite: { [weak self] text in
                self?.handleAcceptRewrite(text)
            },
            onClose: { [weak self] in
                self?.handleReviewSelectionPanelClosed()
            }
        )
        reviewSelectionPanelController = controller
        return controller
    }

    // MARK: - About

    public func openAbout() {
        if let existing = aboutWindowController {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: AboutPanel())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "About WriteAssist"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        aboutWindowController = controller

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings

    public func openSettings() {
        if let existing = settingsWindowController {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(
            rootView: SettingsPanel()
                .frame(minWidth: 520, minHeight: 420)
        )

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.setContentSize(NSSize(width: 520, height: 420))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        settingsWindowController = controller

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
