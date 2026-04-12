// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI
import WriteAssistCore

@main
struct WriteAssistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsPanel()
                .frame(minWidth: 520, minHeight: 420)
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shell: AppShellController?
    private var statusBarController: StatusBarController?
    private var reviewSelectionHotKeyController: ReviewSelectionHotKeyController?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        let shellController = AppShellController()
        shell = shellController

        let controller = StatusBarController()
        statusBarController = controller

        controller.setupLauncher(
            onOpenWorkspace: { [weak shellController] in
                shellController?.openWorkspaceWindow()
            },
            onReviewSelection: { [weak shellController] in
                shellController?.triggerReviewSelection()
            },
            onOpenSettings: { [weak shellController] in
                shellController?.openSettings()
            }
        )

        let hotKeyController = ReviewSelectionHotKeyController(onActivate: { [weak shellController] in
            shellController?.triggerReviewSelection()
        })
        hotKeyController.start()
        reviewSelectionHotKeyController = hotKeyController

        shellController.start(statusBarController: controller)
        NSApp.setActivationPolicy(.accessory)
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        WritingStatsStore.shared.endSession()
        reviewSelectionHotKeyController?.stop()
        reviewSelectionHotKeyController = nil
        statusBarController?.teardown()
        shell?.stop()
    }
}
