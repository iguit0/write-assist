// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit

struct GlobalKeyEvent: Sendable, Equatable {
    let keyCode: UInt16
    let characters: String?
    let charactersIgnoringModifiers: String?
    let modifiers: GlobalKeyModifiers
}

struct GlobalKeyModifiers: OptionSet, Sendable, Equatable {
    let rawValue: Int

    static let command = GlobalKeyModifiers(rawValue: 1 << 0)
    static let control = GlobalKeyModifiers(rawValue: 1 << 1)
    static let option = GlobalKeyModifiers(rawValue: 1 << 2)
    static let shift = GlobalKeyModifiers(rawValue: 1 << 3)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

struct GlobalKeyHandlerToken: Hashable, Sendable {
    let id: UUID
}

@MainActor
final class GlobalKeyEventRouter {
    static let shared = GlobalKeyEventRouter()

    private struct HandlerEntry {
        let token: GlobalKeyHandlerToken
        let priority: Int
        let registrationOrder: Int
        let handler: (GlobalKeyEvent) -> Bool
    }

    private var monitor: Any?
    private var handlers: [HandlerEntry] = []
    private var nextRegistrationOrder = 0

    init(installSystemMonitor: Bool = true) {
        guard installSystemMonitor else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyEvent = Self.convert(event)
            Task { @MainActor in
                self?.dispatch(keyEvent)
            }
        }
    }

    func register(priority: Int, handler: @escaping (GlobalKeyEvent) -> Bool) -> GlobalKeyHandlerToken {
        nextRegistrationOrder += 1
        let token = GlobalKeyHandlerToken(id: UUID())
        handlers.append(HandlerEntry(
            token: token,
            priority: priority,
            registrationOrder: nextRegistrationOrder,
            handler: handler
        ))
        return token
    }

    func unregister(_ token: GlobalKeyHandlerToken) {
        handlers.removeAll { $0.token == token }
    }

    func dispatch(_ event: GlobalKeyEvent) {
        let sortedHandlers = handlers.sorted {
            if $0.priority == $1.priority {
                return $0.registrationOrder > $1.registrationOrder
            }
            return $0.priority > $1.priority
        }

        for entry in sortedHandlers where entry.handler(event) {
            return
        }
    }

    private static func convert(_ event: NSEvent) -> GlobalKeyEvent {
        var modifiers: GlobalKeyModifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }

        return GlobalKeyEvent(
            keyCode: event.keyCode,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifiers: modifiers
        )
    }
}
