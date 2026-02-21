# HUD Keyboard Navigation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add keyboard arrow navigation, Enter-to-apply, and shortcut keys (i/d/Esc) to the ErrorHUDPanel's inline suggestion popup.

**Architecture:** A shared `@Observable` class (`HUDKeyboardState`) bridges the AppKit key monitor in `ErrorHUDPanel` to the SwiftUI `InlineSuggestionView`. A dedicated global `NSEvent` monitor is installed when the HUD panel is shown and removed on dismiss. `StatusBarController` checks `ErrorHUDPanel.isAcceptingKeyboardInput` to avoid dismissing the HUD on navigation keystrokes.

**Tech Stack:** Swift 6, AppKit (NSEvent global monitor), SwiftUI (@Observable), macOS Accessibility

---

### Task 1: Add HUDKeyboardState observable class

**Files:**
- Modify: `Sources/ErrorHUDPanel.swift` (insert before `InlineSuggestionView` struct, around line 304)

**Step 1: Add the HUDKeyboardState class**

Insert this class just above the `// MARK: - Inline Suggestion Content View` comment (line 304):

```swift
// MARK: - Keyboard Navigation State

/// Shared state between ErrorHUDPanel (key monitor) and InlineSuggestionView
/// (rendering). ErrorHUDPanel mutates; InlineSuggestionView observes.
@MainActor
@Observable
final class HUDKeyboardState {
    var selectedIndex: Int?
    let suggestionCount: Int

    init(suggestionCount: Int) {
        self.suggestionCount = suggestionCount
    }

    func moveDown() {
        guard suggestionCount > 0 else { return }
        if let current = selectedIndex {
            selectedIndex = (current + 1) % suggestionCount
        } else {
            selectedIndex = 0
        }
    }

    func moveUp() {
        guard suggestionCount > 0 else { return }
        if let current = selectedIndex {
            selectedIndex = (current - 1 + suggestionCount) % suggestionCount
        } else {
            selectedIndex = suggestionCount - 1
        }
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED (class is declared but not yet used — no warnings expected since it's referenced by name)

**Step 3: Commit**

```bash
git add Sources/ErrorHUDPanel.swift
git commit -m "feat: add HUDKeyboardState observable for HUD keyboard navigation"
```

---

### Task 2: Wire keyboard state into InlineSuggestionView

**Files:**
- Modify: `Sources/ErrorHUDPanel.swift` — `InlineSuggestionView` struct (lines 308-531)

**Step 1: Add keyboardState property and update suggestion highlighting**

In `InlineSuggestionView`, add a new property after `onAddToDictionary`:

```swift
var keyboardState: HUDKeyboardState
```

Then update the suggestion row background (around line 393-397). Replace the existing `.background(...)` block on the suggestion button:

```swift
// EXISTING (remove):
.background(
    RoundedRectangle(cornerRadius: 4)
        .fill(Color.primary.opacity(
            hoveredSuggestion == suggestion ? 0.07 : 0.0
        ))
)
```

With:

```swift
// NEW:
.background(
    RoundedRectangle(cornerRadius: 4)
        .fill(Color.primary.opacity(
            suggestionOpacity(for: suggestion, at: index)
        ))
)
```

To get the `index`, change the `ForEach` to use `Array(issue.suggestions.prefix(4)).enumerated()`. Replace:

```swift
ForEach(issue.suggestions.prefix(4), id: \.self) { suggestion in
```

With:

```swift
ForEach(Array(issue.suggestions.prefix(4).enumerated()), id: \.element) { index, suggestion in
```

Add a private helper method to `InlineSuggestionView`:

```swift
private func suggestionOpacity(for suggestion: String, at index: Int) -> Double {
    if keyboardState.selectedIndex == index {
        return 0.12
    } else if hoveredSuggestion == suggestion {
        return 0.07
    }
    return 0.0
}
```

**Step 2: Update the InlineSuggestionView initializer call in ErrorHUDPanel.show()**

In `ErrorHUDPanel.show()`, store the keyboard state and pass it to the view. Add a stored property to `ErrorHUDPanel`:

```swift
private var keyboardState: HUDKeyboardState?
```

In `show()`, create the state before building the view (after the `addToDictionary` closure, around line 68):

```swift
let suggestionCount = min(issue.suggestions.count, 4)
let kbState = HUDKeyboardState(suggestionCount: suggestionCount)
self.keyboardState = kbState
```

Update the `InlineSuggestionView(...)` initializer call (line 70) to pass `keyboardState`:

```swift
let contentView = InlineSuggestionView(
    issue: issue,
    onApply: { [weak self, weak viewModel] suggestion in
        logger.debug("onApply: user selected '\(suggestion)' for '\(issue.word)'")
        self?.dismiss()
        viewModel?.applyCorrection(issue, correction: suggestion)
    },
    onIgnore: { [weak self, weak viewModel] in
        logger.debug("onIgnore: user ignored '\(issue.word)'")
        viewModel?.ignoreIssue(issue)
        self?.dismiss()
    },
    onDismiss: { [weak self] in
        logger.debug("onDismiss: user dismissed HUD")
        self?.dismiss()
    },
    onAddToDictionary: addToDictionary,
    keyboardState: kbState
)
```

In `dismiss()`, clear the keyboard state:

```swift
keyboardState = nil
```

**Step 3: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add Sources/ErrorHUDPanel.swift
git commit -m "feat: wire HUDKeyboardState into InlineSuggestionView for selection highlighting"
```

---

### Task 3: Add keyboard hint bar to InlineSuggestionView

**Files:**
- Modify: `Sources/ErrorHUDPanel.swift` — `InlineSuggestionView.body` (around lines 515-517, after the action buttons HStack)

**Step 1: Add the hint bar**

After the action buttons `HStack` closing brace and its padding modifiers (after line 517: `.padding(.vertical, 7)`), add:

```swift
// Keyboard shortcut hints
HStack(spacing: 0) {
    Text("↑↓ navigate · ↵ apply · i ignore · esc dismiss")
        .font(.system(size: 9))
        .foregroundStyle(.quaternary)
    if issue.type == .spelling, onAddToDictionary != nil {
        Text(" · d add to dict")
            .font(.system(size: 9))
            .foregroundStyle(.quaternary)
    }
}
.padding(.horizontal, 12)
.padding(.bottom, 6)
.padding(.top, 2)
```

**Step 2: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Sources/ErrorHUDPanel.swift
git commit -m "feat: add keyboard shortcut hint bar to HUD popup"
```

---

### Task 4: Add global key monitor to ErrorHUDPanel

**Files:**
- Modify: `Sources/ErrorHUDPanel.swift` — `ErrorHUDPanel` class (lines 15-302)

**Step 1: Add stored properties for key monitor and callbacks**

Add these properties to `ErrorHUDPanel` (after `showCooldown`, around line 27):

```swift
/// Global key event monitor, active only while the HUD panel is visible.
private var keyMonitor: Any?

/// Whether the HUD is intercepting keyboard events (panel is shown).
/// StatusBarController checks this to avoid dismissing on navigation keys.
private(set) var isAcceptingKeyboardInput = false

/// Stored callbacks for keyboard-triggered actions.
private var onApplyCallback: ((String) -> Void)?
private var onIgnoreCallback: (() -> Void)?
private var onDismissCallback: (() -> Void)?
private var onAddToDictionaryCallback: (() -> Void)?
private var currentSuggestions: [String] = []
```

**Step 2: Add installKeyMonitor() and removeKeyMonitor() methods**

Add these methods after `dismiss()` (around line 146), before `// MARK: - Panel Presentation`:

```swift
// MARK: - Keyboard Navigation

private func installKeyMonitor() {
    removeKeyMonitor()
    isAcceptingKeyboardInput = true

    keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
        Task { @MainActor in
            self?.handleKeyEvent(event)
        }
    }
    logger.debug("installKeyMonitor: keyboard navigation active")
}

private func removeKeyMonitor() {
    if let monitor = keyMonitor {
        NSEvent.removeMonitor(monitor)
        keyMonitor = nil
    }
    isAcceptingKeyboardInput = false
}

private func handleKeyEvent(_ event: NSEvent) {
    // Ignore events with command/control/option modifiers
    let modifiers = event.modifierFlags.intersection([.command, .control, .option])
    guard modifiers.isEmpty else { return }

    let keyCode = event.keyCode

    switch keyCode {
    case 125: // Down Arrow
        keyboardState?.moveDown()
        logger.debug("handleKeyEvent: ↓ — selectedIndex=\(self.keyboardState?.selectedIndex ?? -1)")

    case 126: // Up Arrow
        keyboardState?.moveUp()
        logger.debug("handleKeyEvent: ↑ — selectedIndex=\(self.keyboardState?.selectedIndex ?? -1)")

    case 36, 76: // Return / Enter
        if let index = keyboardState?.selectedIndex,
           index < currentSuggestions.count {
            let suggestion = currentSuggestions[index]
            logger.debug("handleKeyEvent: ↵ — applying '\(suggestion)'")
            onApplyCallback?(suggestion)
        }

    case 53: // Escape
        logger.debug("handleKeyEvent: esc — dismissing")
        onDismissCallback?()

    default:
        // Check for character shortcuts
        if let chars = event.charactersIgnoringModifiers?.lowercased() {
            switch chars {
            case "i":
                logger.debug("handleKeyEvent: 'i' — ignoring issue")
                onIgnoreCallback?()
            case "d":
                if onAddToDictionaryCallback != nil {
                    logger.debug("handleKeyEvent: 'd' — adding to dictionary")
                    onAddToDictionaryCallback?()
                } else {
                    // Not a spelling issue — dismiss and let key pass through
                    dismiss()
                }
            default:
                // Non-navigation key — dismiss HUD
                dismiss()
            }
        }
    }
}
```

**Step 3: Wire up the monitor and callbacks in show()**

In `show()`, after creating the callbacks and before creating `contentView`, store the callbacks and suggestions:

```swift
// Store for keyboard navigation
currentSuggestions = Array(issue.suggestions.prefix(4))
onApplyCallback = { [weak self, weak viewModel] suggestion in
    logger.debug("onApply: user selected '\(suggestion)' for '\(issue.word)'")
    self?.dismiss()
    viewModel?.applyCorrection(issue, correction: suggestion)
}
onIgnoreCallback = { [weak self, weak viewModel] in
    logger.debug("onIgnore: user ignored '\(issue.word)'")
    viewModel?.ignoreIssue(issue)
    self?.dismiss()
}
onDismissCallback = { [weak self] in
    logger.debug("onDismiss: user dismissed HUD")
    self?.dismiss()
}
onAddToDictionaryCallback = addToDictionary
```

Then update the `InlineSuggestionView` initializer to reuse these stored callbacks:

```swift
let contentView = InlineSuggestionView(
    issue: issue,
    onApply: { [weak self] suggestion in self?.onApplyCallback?(suggestion) },
    onIgnore: { [weak self] in self?.onIgnoreCallback?() },
    onDismiss: { [weak self] in self?.onDismissCallback?() },
    onAddToDictionary: addToDictionary,
    keyboardState: kbState
)
```

In `presentPanel()`, add the key monitor installation at the end (after `p.animator().alphaValue = 1`):

In `show()`, inside the Task block, after `self.presentPanel(...)`, add:

```swift
self.installKeyMonitor()
```

**Step 4: Clean up in dismiss()**

In `dismiss()`, add cleanup before the existing `guard let p = panel else { return }`:

```swift
removeKeyMonitor()
onApplyCallback = nil
onIgnoreCallback = nil
onDismissCallback = nil
onAddToDictionaryCallback = nil
currentSuggestions = []
keyboardState = nil
```

Note: move the `keyboardState = nil` from Task 2 into this block so all cleanup is together.

**Step 5: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add Sources/ErrorHUDPanel.swift
git commit -m "feat: add global key monitor for HUD keyboard navigation"
```

---

### Task 5: Coordinate with StatusBarController

**Files:**
- Modify: `Sources/StatusBarController.swift` (lines 87-95)

**Step 1: Skip HUD dismissal when keyboard navigation is active**

Replace the existing `onKeystroke` handler (lines 88-95):

```swift
// EXISTING (replace):
inputMonitor.onKeystroke = { [weak self] in
    Task { @MainActor in
        if self?.hudPanel != nil {
            logger.debug("onKeystroke: dismissing HUD on user typing")
        }
        self?.hudPanel?.dismiss()
    }
}
```

With:

```swift
// NEW:
inputMonitor.onKeystroke = { [weak self] in
    Task { @MainActor in
        // When the HUD's keyboard monitor is active, it handles all key
        // events itself (including dismissal for non-navigation keys).
        // Don't dismiss here — it would race with the HUD's own handler.
        guard self?.hudPanel?.isAcceptingKeyboardInput != true else {
            return
        }
        self?.hudPanel?.dismiss()
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Sources/StatusBarController.swift
git commit -m "feat: skip HUD dismissal when keyboard navigation is active"
```

---

### Task 6: Final build verification and lint

**Step 1: Full build**

Run: `swift build`
Expected: BUILD SUCCEEDED with zero errors and zero warnings

**Step 2: Lint**

Run: `swiftlint`
Expected: Zero violations

**Step 3: Manual smoke test**

Run: `swift run`

Test scenarios:
1. Type a misspelled word → HUD appears → press ↓ → first suggestion highlights → press ↵ → correction applied
2. Type a misspelled word → HUD appears → press ↑ → last suggestion highlights → press ↓ wraps to first
3. Type a misspelled word → HUD appears → press `i` → issue ignored, HUD dismissed
4. Type a misspelled word → HUD appears → press `d` → word added to dictionary (spelling only)
5. Type a misspelled word → HUD appears → press Esc → HUD dismissed
6. Type a misspelled word → HUD appears → type a regular character → HUD dismissed, character goes to editor
7. Verify the keyboard hint bar is visible at the bottom of the HUD
8. Verify hint bar shows "d add to dict" only for spelling issues

**Step 4: Final commit (if any lint fixes needed)**

```bash
git add Sources/ErrorHUDPanel.swift Sources/StatusBarController.swift
git commit -m "fix: lint and cleanup for HUD keyboard navigation"
```
