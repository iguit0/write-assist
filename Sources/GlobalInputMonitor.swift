// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import os

private let logger = Logger(subsystem: "com.writeassist", category: "GlobalInputMonitor")

@MainActor
@Observable
public final class GlobalInputMonitor {
    public private(set) var hasAccessibilityPermission = false

    private let keyEventRouter: GlobalKeyEventRouter
    private var keyHandlerToken: GlobalKeyHandlerToken?
    private var buffer = ""
    private let maxBufferSize = 500
    weak var viewModel: DocumentViewModel?

    private var pendingSelectAll = false

    var onKeystroke: (() -> Void)?
    var onWordBoundaryTyped: (() -> Void)?
    var onAccessibilityPermissionChanged: ((Bool) -> Void)?
    var onSecureContextDetected: (() -> Void)?

    private var permissionTimer: Timer?

    public init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
        self.keyEventRouter = .shared
        checkPermission()
        startPermissionPolling()
    }

    init(
        viewModel: DocumentViewModel,
        keyEventRouter: GlobalKeyEventRouter
    ) {
        self.viewModel = viewModel
        self.keyEventRouter = keyEventRouter
        checkPermission()
        startPermissionPolling()
    }

    @MainActor
    public func cleanup() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    func checkPermission() {
        let trusted = AXIsProcessTrusted()
        let wasPermitted = hasAccessibilityPermission
        hasAccessibilityPermission = trusted

        if trusted && !wasPermitted {
            startMonitoring()
            onAccessibilityPermissionChanged?(true)
        } else if !trusted && wasPermitted {
            stopMonitoring()
            buffer.removeAll(keepingCapacity: true)
            viewModel?.textDidChange("")
            onAccessibilityPermissionChanged?(false)
        }
    }

    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermission()
            }
        }
    }

    func requestPermission() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func startMonitoring() {
        guard AXIsProcessTrusted(), keyHandlerToken == nil else { return }

        keyHandlerToken = keyEventRouter.register(priority: 100) { [weak self] event in
            self?.handle(event: event)
            return false
        }
    }

    public func stopMonitoring() {
        if let keyHandlerToken {
            keyEventRouter.unregister(keyHandlerToken)
        }
        keyHandlerToken = nil
    }

    private func handle(event: GlobalKeyEvent) {
        if AXHelper.isSecureInputEnabled {
            clearBufferForSecureContext(reason: "secure input enabled")
            onSecureContextDetected?()
            return
        }
        if let focusedElement = AXHelper.focusedElement(skipSelf: true),
           !AXHelper.isSafeToInspect(focusedElement) {
            clearBufferForSecureContext(reason: "secure field focused")
            onSecureContextDetected?()
            return
        }

        let modifiers = event.modifiers.intersection([.command, .control, .option])

        if modifiers.contains(.command) {
            onKeystroke?()
            let keyCode = event.keyCode
            switch keyCode {
            case 0:
                pendingSelectAll = true
            case 6:
                pendingSelectAll = false
                buffer.removeAll(keepingCapacity: true)
                viewModel?.textDidChange("")
            case 7:
                if pendingSelectAll {
                    pendingSelectAll = false
                    buffer.removeAll(keepingCapacity: true)
                    viewModel?.textDidChange("")
                }
            case 9:
                if pendingSelectAll {
                    pendingSelectAll = false
                    buffer.removeAll(keepingCapacity: true)
                    viewModel?.textDidChange("")
                }
            default:
                break
            }
            return
        }

        guard modifiers.isEmpty else { return }

        onKeystroke?()

        let keyCode = event.keyCode

        if pendingSelectAll {
            pendingSelectAll = false
            switch keyCode {
            case 51:
                buffer.removeAll(keepingCapacity: true)
                viewModel?.textDidChange("")
                return
            default:
                buffer.removeAll(keepingCapacity: true)
            }
        }

        let lastCharBeforeKey = buffer.last

        switch keyCode {
        case 51:
            if !buffer.isEmpty {
                buffer.removeLast()
            }
        case 36, 76:
            buffer.append("\n")
        case 53:
            buffer.removeAll(keepingCapacity: true)
        case 48:
            buffer.append("\t")
        default:
            guard let chars = event.characters, !chars.isEmpty else { return }
            for char in chars where char.isLetter || char.isNumber
                || char.isPunctuation || char.isSymbol || char.isWhitespace {
                buffer.append(char)
            }
        }

        if lastCharBeforeKey?.isLetter == true || lastCharBeforeKey?.isNumber == true {
            let isBoundaryKey: Bool
            switch keyCode {
            case 36, 76:
                isBoundaryKey = true
            case 48:
                isBoundaryKey = true
            default:
                isBoundaryKey = event.characters?.first.map { c in
                    c == " " || c == "." || c == "," || c == "?"
                        || c == "!" || c == ";" || c == ":"
                } ?? false
            }
            if isBoundaryKey {
                logger.debug("handle: word boundary after '\(String(lastCharBeforeKey!), privacy: .sensitive)'")
                onWordBoundaryTyped?()
            }
        }

        if buffer.count > maxBufferSize {
            buffer = String(buffer.suffix(maxBufferSize))
        }

        viewModel?.textDidChange(buffer)
    }

    private func clearBufferForSecureContext(reason: String) {
        logger.debug("handle: \(reason, privacy: .public) — clearing buffer")
        buffer.removeAll(keepingCapacity: true)
        viewModel?.textDidChange("")
    }

    var capturedText: String {
        buffer
    }

    func clearBuffer() {
        buffer.removeAll(keepingCapacity: true)
        viewModel?.textDidChange("")
    }

    func replaceInBuffer(old: String, new: String) {
        guard let range = buffer.range(of: old, options: .backwards) else {
            return
        }

        buffer.replaceSubrange(range, with: new)
        if buffer.count > maxBufferSize {
            buffer = String(buffer.suffix(maxBufferSize))
        }

        viewModel?.textDidChange(buffer, isProgrammatic: true)
    }
}
