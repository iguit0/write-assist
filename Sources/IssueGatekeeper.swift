// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

struct IssueGatekeeperUpdate: Sendable {
    let visibleIssues: [WritingIssue]
    let unseenIssueIDs: Set<String>
    let pendingHUDIssues: [WritingIssue]
}

@MainActor
final class IssueGatekeeper {
    private var sessionIgnoredIssueIDs: Set<String> = []
    private var unseenIssueIDs: Set<String> = []
    private var hudShownIssueIDs: Set<String> = []

    func handleTextChange(isProgrammatic: Bool) {
        sessionIgnoredIssueIDs.removeAll()
        if !isProgrammatic {
            hudShownIssueIDs.removeAll()
        }
    }

    func reconcile(
        detectedIssues: [WritingIssue],
        previousVisibleIssues: [WritingIssue],
        ignoreStore: IgnoreRulesStore,
        recentlyCorrectedIssueIDs: Set<String>,
        allowHUD: Bool
    ) -> IssueGatekeeperUpdate {
        let filtered = detectedIssues.filter {
            !sessionIgnoredIssueIDs.contains($0.id)
                && !ignoreStore.isIgnored(word: $0.word, ruleID: $0.ruleID)
        }

        let visibleIDs = Set(filtered.map(\.id))
        unseenIssueIDs.formIntersection(visibleIDs)
        hudShownIssueIDs.formIntersection(visibleIDs)

        let previousIDs = Set(previousVisibleIssues.map(\.id))
        let brandNewIDs = Set(filtered.filter { !previousIDs.contains($0.id) }.map(\.id))
        unseenIssueIDs.formUnion(brandNewIDs)

        guard allowHUD else {
            return IssueGatekeeperUpdate(
                visibleIssues: filtered,
                unseenIssueIDs: unseenIssueIDs,
                pendingHUDIssues: []
            )
        }

        let pendingHUD = filtered.filter {
            !hudShownIssueIDs.contains($0.id) && !recentlyCorrectedIssueIDs.contains($0.id)
        }
        hudShownIssueIDs.formUnion(pendingHUD.map(\.id))

        return IssueGatekeeperUpdate(
            visibleIssues: filtered,
            unseenIssueIDs: unseenIssueIDs,
            pendingHUDIssues: pendingHUD
        )
    }

    @discardableResult
    func ignoreSession(_ issue: WritingIssue) -> Set<String> {
        sessionIgnoredIssueIDs.insert(issue.id)
        unseenIssueIDs.remove(issue.id)
        hudShownIssueIDs.remove(issue.id)
        return unseenIssueIDs
    }

    @discardableResult
    func markAllSeen() -> Set<String> {
        unseenIssueIDs.removeAll()
        return unseenIssueIDs
    }
}
