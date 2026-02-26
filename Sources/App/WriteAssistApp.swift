// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI
import WriteAssistCore

@main
struct WriteAssistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu-bar-only app: no main window.
        // Settings scene prevents "No scene found" warning but is never shown.
        Settings {
            EmptyView()
        }
    }
}

// MARK: - AppDelegate

// Note: Not marked @MainActor at the class level to satisfy nonisolated
// protocol requirements in Swift 6. Individual stored objects are created
// on first access which is always on the main thread from NSApplicationDelegate.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // These are created lazily on first use, always on the main thread.
    private var viewModel: DocumentViewModel?
    private var statusBarController: StatusBarController?
    private var inputMonitor: GlobalInputMonitor?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let vm = DocumentViewModel()
        let monitor = GlobalInputMonitor(viewModel: vm)
        let controller = StatusBarController()

        viewModel = vm
        inputMonitor = monitor
        statusBarController = controller

        // Wire the input monitor reference so DocumentViewModel can update
        // the buffer after applying a correction (prevents re-detecting corrected words).
        vm.inputMonitor = monitor

        // Set up status bar item + popover FIRST, then hide Dock icon.
        // Setting activation policy before creating the NSStatusItem can
        // prevent the item from appearing in some macOS configurations.
        controller.setup(viewModel: vm, inputMonitor: monitor)

        // Hide Dock icon — must happen after status item is created
        // so macOS knows the app has a presence in the UI.
        NSApp.setActivationPolicy(.accessory)

        // Start monitoring if permission already granted
        if monitor.hasAccessibilityPermission {
            monitor.startMonitoring()
        }
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        WritingStatsStore.shared.endSession()
        inputMonitor?.cleanup()
        inputMonitor?.stopMonitoring()
        statusBarController?.teardown()
    }
}
