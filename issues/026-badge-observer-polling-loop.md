# Status bar badge uses 300 ms polling instead of reactive `@Observable` observation

**Labels:** `performance` `P2-medium`  
**Status:** 🆕 New

## Description

`StatusBarController.startBadgeObserver` runs a `Task` loop that polls `viewModel.totalActiveIssueCount` and `viewModel.unseenIssueIDs.count` every 300 ms via `Task.sleep`. This wastes CPU cycles continuously, even when no writing is happening, and introduces up to 300 ms of latency between a new issue being detected and the badge updating.

Since `DocumentViewModel` is already `@Observable`, reactive observation is directly available without polling.

## Affected Files

- `Sources/StatusBarController.swift` — `startBadgeObserver()`, approximately lines 200–225

## Proposed Fix

Replace the polling loop with `withObservationTracking`:

```swift
func startBadgeObserver() {
    observeBadgeChanges()
}

private func observeBadgeChanges() {
    withObservationTracking {
        // Access the observed properties inside this closure
        let count = viewModel.totalActiveIssueCount
        let unseen = viewModel.unseenIssueIDs.count
        updateBadge(count: count, unseen: unseen)
    } onChange: { [weak self] in
        Task { @MainActor in
            self?.observeBadgeChanges()  // re-register after each change
        }
    }
}
```

This update fires immediately on every change rather than lagging by up to 300 ms, and uses zero CPU between changes.
