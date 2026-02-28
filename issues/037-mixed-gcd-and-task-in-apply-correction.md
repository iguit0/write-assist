# `applyCorrection` mixes GCD `DispatchWorkItem` and Swift `Task` inconsistently

**Labels:** `refactor` `P3-low`  
**Status:** ✅ Fixed — replaced all `DispatchWorkItem` + `DispatchQueue.main.asyncAfter` and `DispatchQueue.global().async` in the correction and selection-replacement flows with `Task { @MainActor }` and `Task.detached`; added a `fallbackTask` property for structured cancellation (#037)

## Description

`DocumentViewModel.applyCorrection` uses both GCD (`DispatchQueue.main.asyncAfter`) and Swift concurrency (`Task { @MainActor }`) in the same flow for cleanup and fallback timing. These two mechanisms schedule work on the main actor in subtly different ways and interact in non-obvious order:

- `DispatchQueue.main.asyncAfter` adds to the GCD main queue
- `Task { @MainActor }` adds to the Swift concurrency cooperative thread pool routed to the main actor

When both are enqueued, their relative ordering is undefined and can vary across OS versions. This makes the correction flow hard to reason about and can cause the `isCorrectionInFlight` flag to be cleared at unexpected times.

## Affected Files

- `Sources/DocumentViewModel.swift` — `applyCorrection(_:correction:)` and related cleanup paths

## Proposed Fix

Replace all `DispatchQueue.main.asyncAfter` calls in the correction flow with `Task { @MainActor in try? await Task.sleep(for: .milliseconds(N)) }` to make all async work use a single concurrency mechanism:

```swift
// Before:
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
    self?.isCorrectionInFlight = false
}

// After:
Task { @MainActor in
    try? await Task.sleep(for: .milliseconds(300))
    self.isCorrectionInFlight = false
}
```

Note: `Task { @MainActor }` tasks support structured cancellation via `Task.cancel()`, unlike `DispatchWorkItem`. Store the cleanup task and cancel it if a new correction arrives before the delay completes.
