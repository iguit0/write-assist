# `HighlightedTextView.Coordinator` retains stale `onSelectionChanged` callback after re-render

**Labels:** `bug` `P1-high`  
**Status:** 🔧 In Progress — see `docs/plans/2026-02-24-writing-issue-and-ai-service-plan.md` (Task 3)

## Description

`HighlightedTextView.makeCoordinator()` captures `onSelectionChanged` by value at construction time. SwiftUI only calls `makeCoordinator()` **once** per view lifetime. If the parent view re-renders with a different closure (e.g., because a captured value changed), the coordinator continues to use the stale original closure. New text selections are silently dispatched to the wrong handler.

```swift
// makeCoordinator is called once; subsequent renders don't update the coordinator
func makeCoordinator() -> Coordinator {
    Coordinator(onSelectionChanged: onSelectionChanged)  // captured once
}

class Coordinator: NSObject, NSTextViewDelegate {
    let onSelectionChanged: ...  // `let` — immutable, never refreshed
}
```

## Affected Files

- `Sources/HighlightedTextView.swift` — `makeCoordinator()` and `Coordinator.onSelectionChanged`

## Proposed Fix

Change `Coordinator.onSelectionChanged` from `let` to `var` and refresh it in `updateNSView(_:context:)`:

```swift
func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.onSelectionChanged = onSelectionChanged  // keep in sync
    // ... rest of update
}
```

Full implementation in `docs/plans/2026-02-24-writing-issue-and-ai-service-plan.md` (Task 3).
