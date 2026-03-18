// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

@preconcurrency import AppKit

struct PasteboardTransaction: Equatable {
    let previousString: String?
    let changeCountBeforeWrite: Int
    let changeCountAfterWrite: Int
    let payload: String

    @discardableResult
    static func write(
        _ payload: String,
        pasteboard: NSPasteboard = .general
    ) -> PasteboardTransaction {
        let previousString = pasteboard.string(forType: .string)
        let before = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)
        let after = pasteboard.changeCount
        return PasteboardTransaction(
            previousString: previousString,
            changeCountBeforeWrite: before,
            changeCountAfterWrite: after,
            payload: payload
        )
    }

    func shouldRestore(
        currentString: String?,
        currentChangeCount: Int
    ) -> Bool {
        currentChangeCount == changeCountAfterWrite && currentString == payload
    }

    func restoreIfUnchanged(pasteboard: NSPasteboard = .general) {
        guard shouldRestore(
            currentString: pasteboard.string(forType: .string),
            currentChangeCount: pasteboard.changeCount
        ) else { return }
        pasteboard.clearContents()
        if let previousString {
            pasteboard.setString(previousString, forType: .string)
        }
    }
}
