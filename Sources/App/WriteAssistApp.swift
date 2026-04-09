// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI
import WriteAssistCore

@main
struct WriteAssistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shell: AppShellController?
    private var statusBarController: StatusBarController?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let shellController = AppShellController()
        shell = shellController

        let controller = StatusBarController()
        statusBarController = controller

        controller.setupLauncher(
            onOpenReview: { [weak shellController] in
                shellController?.openReviewWindow()
            },
            onReviewSelection: { [weak shellController] in
                Task { await shellController?.reviewSelection() }
            },
            onOpenSettings: { [weak shellController] in
                shellController?.openSettings()
            }
        )

        shellController.start(statusBarController: controller)
        NSApp.setActivationPolicy(.accessory)
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        WritingStatsStore.shared.endSession()
        statusBarController?.teardown()
        shell?.stop()
    }
}
