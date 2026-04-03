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

    // New workbench shell
    private var shell: AppShellController?

    // Legacy inline path — kept compilable during migration
    private var viewModel: DocumentViewModel?
    private var statusBarController: StatusBarController?
    private var inputMonitor: GlobalInputMonitor?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // --- New workbench shell ---
        let shellController = AppShellController(mode: .reviewWorkbenchHybrid)
        shell = shellController

        // --- Legacy inline path (kept compilable, still the active UI for now) ---
        let vm = DocumentViewModel()
        let monitor = GlobalInputMonitor(viewModel: vm)
        let controller = StatusBarController()

        viewModel = vm
        inputMonitor = monitor
        statusBarController = controller

        vm.inputMonitor = monitor

        // Legacy popover setup — still active in .reviewWorkbenchHybrid mode.
        // setupLauncher(onOpenReview:onReviewSelection:onOpenSettings:) exists on StatusBarController
        // and will replace this call when the workbench window becomes the primary surface (Phase 2).
        controller.setup(viewModel: vm, inputMonitor: monitor)

        NSApp.setActivationPolicy(.accessory)

        if monitor.hasAccessibilityPermission {
            monitor.startMonitoring()
        }

        shellController.start(statusBarController: controller)
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        WritingStatsStore.shared.endSession()
        inputMonitor?.cleanup()
        inputMonitor?.stopMonitoring()
        statusBarController?.teardown()
        shell?.stop()
    }
}
