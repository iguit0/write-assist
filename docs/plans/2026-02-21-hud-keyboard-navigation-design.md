# HUD Keyboard Navigation Design

## Overview

Add keyboard navigation to the ErrorHUDPanel's inline suggestion popup so users can select and apply corrections without using the mouse. The HUD is a non-activating NSPanel that must not steal focus from the user's text editor.

## Architecture

**Approach:** HUD-scoped global NSEvent monitor (Approach A).

A dedicated `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` is installed inside `ErrorHUDPanel` when the panel is shown, and removed when dismissed. This keeps all keyboard logic self-contained within the HUD without coupling to `GlobalInputMonitor`.

**State:** `@State var selectedIndex: Int?` in `InlineSuggestionView`. `nil` = no selection (opt-in mode). Set to `0` on first Down Arrow press. Cycles through `0..<suggestions.prefix(4).count`.

**Event flow:**
1. `ErrorHUDPanel.show()` installs the key monitor alongside the panel
2. Navigation keys (↑/↓/Enter/Escape/i/d) are routed to `InlineSuggestionView` via a callback
3. `ErrorHUDPanel.dismiss()` removes the key monitor
4. A flag `isAcceptingKeyboardInput` on `ErrorHUDPanel` lets `StatusBarController` skip HUD dismissal for navigation keys

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| ↓ | Select next suggestion (or first if none selected) |
| ↑ | Select previous suggestion (wraps around) |
| Enter/Return | Apply selected suggestion (no-op if none selected) |
| Escape | Dismiss the HUD |
| `i` | Ignore the issue |
| `d` | Add word to dictionary (spelling only) |

Arrow keys wrap around (Down on last → first, Up on first → last). Any non-navigation key dismisses the HUD and passes through normally.

## Visual Design

**Selection highlight:** `Color.primary.opacity(0.12)` rounded rectangle background on the selected row (slightly stronger than the existing hover at `0.07`).

**Keyboard hint bar:** Below the action buttons:
```
↑↓ navigate · ↵ apply · i ignore · esc dismiss
```
For spelling issues: `· d add to dict` appended.

Styled: `font(.system(size: 9))`, `.foregroundStyle(.quaternary)`.

## Edge Cases

- **No suggestions:** Arrow keys are no-op. Only Escape/i/d work.
- **AI Rewrite:** Not included in keyboard navigation (mouse-only).
- **Monitor lifecycle:** Old monitor removed before new one is installed on re-show.
- **Rapid keys:** Synchronous @MainActor state updates prevent race conditions.

## Files to Modify

- `Sources/ErrorHUDPanel.swift` — key monitor, keyboard event routing, `isAcceptingKeyboardInput` flag
- `Sources/StatusBarController.swift` — check `isAcceptingKeyboardInput` before dismissing HUD on keystroke
