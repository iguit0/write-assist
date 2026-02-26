# HUD has no keyboard navigation (↑↓ Enter, i, d, Esc)

**Labels:** `enhancement` `accessibility` `P2-medium`  
**Status:** 🔧 In Progress — see `docs/plans/2026-02-21-hud-keyboard-navigation-plan.md`

## Description

The Error HUD panel appears near the text caret when an issue is detected, but it can only be interacted with by moving the mouse to click a suggestion button. This disrupts the writing flow — the user must leave the keyboard to accept or dismiss a correction.

Expected keyboard shortcuts for the HUD:
- `↑` / `↓` — navigate between suggestions (with visual highlight)
- `↵` (Return/Enter) — apply the selected suggestion
- `i` — ignore the issue for this session
- `d` — add word to personal dictionary (spelling issues only)
- `Esc` — dismiss without action
- Any other key — dismiss HUD and let the key pass through to the editor

## Affected Files

- `Sources/ErrorHUDPanel.swift`
- `Sources/StatusBarController.swift`

## Proposed Fix

See `docs/plans/2026-02-21-hud-keyboard-navigation-plan.md` for the complete 6-task implementation plan:

1. Add `HUDKeyboardState` `@Observable` class for navigation state
2. Wire keyboard state into `InlineSuggestionView` for suggestion highlighting
3. Add keyboard shortcut hint bar to the HUD footer
4. Add global `NSEvent` key monitor active only while HUD is shown
5. Coordinate with `StatusBarController` to avoid conflicting dismiss actions
6. Final build + lint verification

## Additional Context

The plan also adds a keyboard hint bar ("↑↓ navigate · ↵ apply · i ignore · esc dismiss") at the bottom of the HUD so users discover the shortcuts without reading documentation.
