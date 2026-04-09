// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import Foundation
import Testing
@testable import WriteAssistCore

@Suite("AXHelper secure inspection")
struct AXHelperInspectionDecisionTests {
    @Test("denies inspection when secure input is enabled")
    func deniesForSecureInput() {
        let decision = AXHelper.inspectionDecision(
            secureInputEnabled: true,
            role: kAXTextFieldRole as String,
            subrole: nil
        )
        #expect(decision == .denySecureInput)
    }

    @Test("denies inspection for secure text fields")
    func deniesForSecureFieldSubrole() {
        let decision = AXHelper.inspectionDecision(
            secureInputEnabled: false,
            role: kAXTextFieldRole as String,
            subrole: kAXSecureTextFieldSubrole as String
        )
        #expect(decision == .denySecureField)
    }

    @Test("allows normal text fields")
    func allowsNormalTextField() {
        let decision = AXHelper.inspectionDecision(
            secureInputEnabled: false,
            role: kAXTextFieldRole as String,
            subrole: nil
        )
        #expect(decision == .allow)
    }
}

@Suite("PasteboardTransaction")
struct PasteboardTransactionTests {
    @Test("restores previous clipboard when untouched")
    func restoresPreviousClipboardWhenUntouched() {
        let transaction = PasteboardTransaction(
            previousString: "before",
            changeCountBeforeWrite: 1,
            changeCountAfterWrite: 2,
            payload: "after"
        )

        #expect(transaction.shouldRestore(currentString: "after", currentChangeCount: 2))
    }

    @Test("does not restore when clipboard changed after write")
    func doesNotRestoreIfClipboardChanged() {
        let transaction = PasteboardTransaction(
            previousString: "before",
            changeCountBeforeWrite: 1,
            changeCountAfterWrite: 2,
            payload: "after"
        )

        #expect(transaction.shouldRestore(currentString: "user copied", currentChangeCount: 3) == false)
    }

    @Test("restores only owned empty-state clipboard writes")
    func clearsOnlyOwnedClipboardWriteWhenPreviousWasEmpty() {
        let transaction = PasteboardTransaction(
            previousString: nil,
            changeCountBeforeWrite: 4,
            changeCountAfterWrite: 5,
            payload: "temporary"
        )

        #expect(transaction.shouldRestore(currentString: "temporary", currentChangeCount: 5))
        #expect(transaction.shouldRestore(currentString: "temporary", currentChangeCount: 6) == false)
    }
}


