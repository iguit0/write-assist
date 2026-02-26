# AX focused-element boilerplate duplicated in 4 files

**Labels:** `refactor` `architecture` `P2-medium`  
**Status:** 🆕 New

## Description

Four files contain nearly identical boilerplate to read the focused Accessibility element:

```swift
// Pattern repeated 4× across the codebase:
let systemWide = AXUIElementCreateSystemWide()
var focusedElement: CFTypeRef?
AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
guard let element = focusedElement, CFGetTypeID(element) == AXUIElementGetTypeID() else { return }
let axElement = element as! AXUIElement
```

Files containing this pattern:
- `Sources/ErrorHUDPanel.swift` — `queryCaretBounds()`
- `Sources/SelectionMonitor.swift` — `readSelection()`
- `Sources/SelectionSuggestionPanel.swift` — `queryCaretBoundsSync()`
- `Sources/ExternalSpellChecker.swift` — `readWordBeforeCursor()`

Bug fixes to this pattern (e.g., proper error handling for `kAXErrorNoValue`) applied in one copy do not propagate to the others.

## Proposed Fix

Create `Sources/AXHelper.swift` with shared utilities:

```swift
enum AXHelper {
    static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &ref)
        guard err == .success,
              let ref,
              CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }
    
    static func caretBounds(for element: AXUIElement) -> CGRect? { ... }
    static func selectedRange(for element: AXUIElement) -> NSRange? { ... }
    static func stringValue(for element: AXUIElement) -> String? { ... }
}
```

All four call sites then collapse to `guard let element = AXHelper.focusedElement() else { return }`.
