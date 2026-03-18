// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import Testing
@testable import WriteAssistCore

@Suite("IssueGatekeeper")
struct IssueGatekeeperTests {
    @MainActor
    @Test("new issues become unseen and HUD-pending")
    func newIssuesBecomeUnseen() {
        let gatekeeper = IssueGatekeeper()
        let issue = WritingIssue(
            type: .spelling,
            ruleID: "spell",
            range: NSRange(location: 0, length: 3),
            word: "teh",
            message: "",
            suggestions: []
        )

        let update = gatekeeper.reconcile(
            detectedIssues: [issue],
            previousVisibleIssues: [],
            ignoreStore: .shared,
            recentlyCorrectedIssueIDs: [],
            allowHUD: true
        )

        #expect(update.unseenIssueIDs.contains(issue.id))
        #expect(update.pendingHUDIssues.count == 1)
    }

    @MainActor
    @Test("programmatic text change preserves HUD shown state")
    func programmaticTextChange() {
        let gatekeeper = IssueGatekeeper()
        let issue = WritingIssue(
            type: .spelling,
            ruleID: "spell",
            range: NSRange(location: 0, length: 3),
            word: "teh",
            message: "",
            suggestions: []
        )

        _ = gatekeeper.reconcile(
            detectedIssues: [issue],
            previousVisibleIssues: [],
            ignoreStore: .shared,
            recentlyCorrectedIssueIDs: [],
            allowHUD: true
        )

        gatekeeper.handleTextChange(isProgrammatic: true)

        let update = gatekeeper.reconcile(
            detectedIssues: [issue],
            previousVisibleIssues: [issue],
            ignoreStore: .shared,
            recentlyCorrectedIssueIDs: [],
            allowHUD: true
        )

        #expect(update.pendingHUDIssues.isEmpty)
    }
}
