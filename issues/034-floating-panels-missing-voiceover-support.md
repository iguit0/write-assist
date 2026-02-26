# HUD and selection panels have no VoiceOver / accessibility labels

**Labels:** `accessibility` `P2-medium`  
**Status:** 🆕 New

## Description

`ErrorHUDPanel` and `SelectionSuggestionPanel` are `NSPanel` windows with `.nonactivatingPanel` style mask containing SwiftUI content views. Neither panel's UI elements have `accessibilityLabel`, `accessibilityHeading`, or `accessibilityElement` modifiers. VoiceOver users cannot:

- Hear the detected issue type or message when the HUD appears
- Navigate to and activate the correction buttons
- Hear the rewrite suggestions in the selection panel
- Use keyboard navigation that VoiceOver expects

This makes the core feature of WriteAssist completely inaccessible to visually impaired users.

## Affected Files

- `Sources/ErrorHUDPanel.swift` — `InlineSuggestionView`
- `Sources/SelectionSuggestionPanel.swift` — `SelectionSuggestionView`
- `Sources/SelectionSuggestionView.swift`

## Proposed Fix

Add accessibility modifiers to key UI elements:

```swift
// In InlineSuggestionView:
Text(issue.message)
    .accessibilityLabel("Writing issue: \(issue.message)")
    .accessibilityAddTraits(.isHeader)

ForEach(issue.suggestions.prefix(4), id: \.self) { suggestion in
    Button(suggestion) { onApply(suggestion) }
        .accessibilityLabel("Apply correction: \(suggestion)")
        .accessibilityHint("Replaces '\(issue.word)' with '\(suggestion)'")
}

Button("Ignore") { onIgnore() }
    .accessibilityLabel("Ignore this issue")

Button("Add to Dictionary") { onAddToDictionary?() }
    .accessibilityLabel("Add \(issue.word) to personal dictionary")
```

Also announce the HUD appearance to VoiceOver when it shows:

```swift
// When HUD appears:
NSAccessibility.post(element: panel.contentView!, notification: .announcementRequested,
    userInfo: [.announcement: "Writing issue detected: \(issue.message)"])
```
