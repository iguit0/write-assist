# `HighlightedTextView` rebuilds the attributed string on every SwiftUI update

**Labels:** `performance` `P2-medium`  
**Status:** 🆕 New

## Description

`HighlightedTextView.updateNSView` unconditionally calls `buildAttributedString()` and replaces the entire `NSTextStorage` on every SwiftUI update pass, even when neither `text` nor `issues` have changed. Because `DocumentViewModel` is `@Observable` and `ContentView.swift` is a 1650-line monolith (see issue [019](019-content-view-1650-line-monolith.md)), unrelated property changes on the view model can trigger `updateNSView`, causing the entire text view to be re-laid out for no reason. On large documents this is visible as a brief flicker.

## Affected Files

- `Sources/HighlightedTextView.swift` — `updateNSView(_:context:)`, approximately lines 38–42

## Proposed Fix

Cache the last rendered state and early-exit if nothing changed:

```swift
class Coordinator: NSObject, NSTextViewDelegate {
    var lastText: String = ""
    var lastIssues: [WritingIssue] = []
    // ...
}

func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.onSelectionChanged = onSelectionChanged
    
    // Early exit if content hasn't changed
    guard text != context.coordinator.lastText ||
          issues.map(\.id) != context.coordinator.lastIssues.map(\.id) else { return }
    
    context.coordinator.lastText = text
    context.coordinator.lastIssues = issues
    
    guard let textView = scrollView.documentView as? NSTextView else { return }
    textView.textStorage?.setAttributedString(buildAttributedString())
}
```

## Additional Context

`WritingIssue` is a `Sendable` value type with a stable `UUID` identity. Comparing `issues.map(\.id)` is O(n) but cheap for the typical small number of issues displayed in the editor.
