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

    // New workbench shell — primary startup path (RW-601)
    private var shell: AppShellController?

    // Legacy inline path — kept compilable for hybrid/fallback mode
    private var viewModel: DocumentViewModel?
    private var statusBarController: StatusBarController?
    private var inputMonitor: GlobalInputMonitor?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Default mode is .reviewWorkbenchOnly (RW-601).
        // Change to .reviewWorkbenchHybrid or .legacyInline to re-enable the
        // ambient-monitor inline path during testing/rollback.
        let shellController = AppShellController(mode: .reviewWorkbenchOnly)
        shell = shellController

        let controller = StatusBarController()
        statusBarController = controller

        if shellController.mode == .reviewWorkbenchOnly {
            // --- Review Workbench path (default) ---
            // Launcher-only menu bar: no ambient monitors, no spell-check panels.
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
        } else {
            // --- Legacy inline path (non-primary, gated) ---
            let vm = DocumentViewModel()
            let monitor = GlobalInputMonitor(viewModel: vm)
            viewModel = vm
            inputMonitor = monitor
            vm.inputMonitor = monitor
            controller.setup(viewModel: vm, inputMonitor: monitor)
            if monitor.hasAccessibilityPermission {
                monitor.startMonitoring()
            }
        }

        shellController.start(statusBarController: controller)
        NSApp.setActivationPolicy(.accessory)
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
