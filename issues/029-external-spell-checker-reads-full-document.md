# `ExternalSpellChecker` reads the entire document text on every word-boundary check

**Labels:** `performance` `P2-medium`  
**Status:** 🆕 New

## Description

`ExternalSpellChecker.readWordBeforeCursor` uses `kAXValueAttribute` to read the **full text content** of the focused element on every word-boundary check (triggered after every typed space or punctuation). For large documents — email drafts, long articles, Markdown files — this reads and allocates the entire document as a Swift `String` just to extract the one word before the cursor.

With an 800 ms debounce this fires at most ~1.25× per second, but the AX `kAXValue` read for a 10,000-word document still transfers ~50–100 KB of text per check.

## Affected Files

- `Sources/ExternalSpellChecker.swift` — `readWordBeforeCursor()`, approximately lines 187–200

## Proposed Fix

Use `kAXStringForRangeParameterizedAttribute` to read only a small window around the cursor:

```swift
func readWordBeforeCursor(element: AXUIElement) -> String? {
    // 1. Read the selected range to find cursor position
    var selectedRangeValue: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
    guard let rangeValue = selectedRangeValue else { return nil }
    var selectedRange = CFRange()
    AXValueGetValue(rangeValue as! AXValue, .cfRange, &selectedRange)
    
    // 2. Read only a 100-char window before the cursor
    let start = max(0, selectedRange.location - 100)
    let length = selectedRange.location - start
    let readRange = CFRangeMake(start, length)
    var rangeParam: AXValue? = AXValueCreate(.cfRange, &readRange) as? AXValue
    var windowValue: CFTypeRef?
    AXUIElementCopyParameterizedAttributeValue(
        element, kAXStringForRangeParameterizedAttribute as CFString,
        rangeParam as CFTypeRef, &windowValue)
    
    // 3. Extract the last word from the window
    guard let window = windowValue as? String else { return nil }
    return window.components(separatedBy: .whitespacesAndNewlines).last
}
```

This reduces the per-check data transfer from O(document length) to O(1) (100 characters).
