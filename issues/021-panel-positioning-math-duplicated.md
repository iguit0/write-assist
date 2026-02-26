# Panel caret-position math duplicated between HUD and selection panel

**Labels:** `refactor` `P2-medium`  
**Status:** 🆕 New

## Description

`ErrorHUDPanel` and `SelectionSuggestionPanel` both contain identical coordinate-conversion math to position a floating panel near the text caret:

- Convert AX top-left screen coordinates to AppKit bottom-left coordinates
- Clamp the panel to stay within screen bounds
- Apply an offset below the caret

This logic is copy-pasted between the two files (~30 lines each). A positioning bug fixed in one panel will not be fixed in the other until someone notices the inconsistency.

## Affected Files

- `Sources/ErrorHUDPanel.swift` — approximately lines 375–410
- `Sources/SelectionSuggestionPanel.swift` — approximately lines 370–400

## Proposed Fix

Create `Sources/PanelPositioning.swift` with a shared static function:

```swift
enum PanelPositioning {
    /// Returns the ideal origin for a floating panel of `panelSize` placed
    /// below the text caret at `caretRect` (in screen coordinates, top-left origin),
    /// clamped to stay within `screen`.
    static func origin(
        caretRect: CGRect,
        panelSize: CGSize,
        screen: NSScreen,
        offsetBelow: CGFloat = 6
    ) -> CGPoint { ... }
}
```

Both `ErrorHUDPanel` and `SelectionSuggestionPanel` call `PanelPositioning.origin(...)` and set `panel.setFrameOrigin(...)`.
