# In-app text editor missing placeholder text

**Labels:** `bug` `ux` `P2-medium`  
**Status:** 🆕 New

## Description

The `HighlightedTextView` in the WriteAssist popover (the "check text here" editor) shows a blank `NSTextView` when empty. There is no placeholder text to guide new users. First-time users may not realise the field is editable or that they can paste text to check it.

The original PRD (US-002) specifies: *"Placeholder text: 'Type or paste your text here…'"*

## Affected Files

- `Sources/HighlightedTextView.swift` — `makeNSView(_:)`, approximately lines 19–35

## Steps to Reproduce

1. Open WriteAssist.
2. Navigate to the Issues tab (default tab).
3. The text editor area is blank with no guidance text.

## Proposed Fix

Add placeholder text to the `NSTextView`:

```swift
// HighlightedTextView.swift — makeNSView
func makeNSView(context: Context) -> NSScrollView {
    // ... existing setup
    
    // Add placeholder via a custom NSTextView subclass or by overlaying a Text view
    textView.placeholderString = "Type or paste your text here…"  // macOS 14+
    
    return scrollView
}
```

For earlier macOS compatibility, overlay a SwiftUI `Text` view on top of the `NSViewRepresentable` using `.overlay` when the text is empty:

```swift
HighlightedTextView(text: $viewModel.currentText, issues: viewModel.issues)
    .overlay(alignment: .topLeading) {
        if viewModel.currentText.isEmpty {
            Text("Type or paste your text here…")
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
        }
    }
```
