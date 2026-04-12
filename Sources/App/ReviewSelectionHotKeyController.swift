// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
@preconcurrency import Carbon.HIToolbox
import OSLog

private let logger = Logger(subsystem: "com.writeassist", category: "ReviewSelectionHotKeyController")
private let reviewSelectionHotKeySignature: OSType = 0x57524153
private let reviewSelectionHotKeyID: UInt32 = 1

/// Registers the global Review Selection shortcut.
///
/// Safety invariant for the Carbon bridge:
/// - this controller is retained by `AppDelegate` for the lifetime of the registration
/// - the callback is installed on the application event target
/// - callback work hops back to the main actor before touching app state
@MainActor
final class ReviewSelectionHotKeyController {
    private let onActivate: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(onActivate: @escaping @MainActor () -> Void) {
        self.onActivate = onActivate
    }

    func start() {
        guard hotKeyRef == nil, eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<ReviewSelectionHotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                return controller.handleHotKeyEvent(event)
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            logger.error("Failed to install review-selection hotkey handler: \(installStatus)")
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: reviewSelectionHotKeySignature,
            id: reviewSelectionHotKeyID
        )
        let modifierFlags = UInt32(controlKey | optionKey | cmdKey)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            modifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            logger.error("Failed to register review-selection hotkey: \(registerStatus)")
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
                self.eventHandlerRef = nil
            }
            return
        }

        logger.info("Registered review-selection hotkey (⌃⌥⌘R)")
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private nonisolated func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr,
              hotKeyID.signature == reviewSelectionHotKeySignature,
              hotKeyID.id == reviewSelectionHotKeyID else {
            return OSStatus(eventNotHandledErr)
        }

        Task { @MainActor [weak self] in
            self?.onActivate()
        }
        return noErr
    }
}
