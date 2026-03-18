// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import Testing
@testable import WriteAssistCore

@Suite("GlobalKeyEventRouter")
struct GlobalKeyEventRouterTests {
    @MainActor
    @Test("higher priority consumes before lower")
    func higherPriorityConsumes() {
        let router = GlobalKeyEventRouter(installSystemMonitor: false)
        var order: [String] = []

        _ = router.register(priority: 100) { _ in
            order.append("low")
            return false
        }

        _ = router.register(priority: 200) { _ in
            order.append("high")
            return true
        }

        router.dispatch(GlobalKeyEvent(
            keyCode: 5,
            characters: "g",
            charactersIgnoringModifiers: "g",
            modifiers: [.command, .shift]
        ))

        #expect(order == ["high"])
    }
}
