# No undo mechanism for corrections applied via AX injection

**Labels:** `enhancement` `ux` `P2-medium`  
**Status:** 🆕 New

## Description

Once `applyCorrection` injects a correction into an external app via `AXUIElementSetAttributeValue`, there is no way to undo the change through WriteAssist. The user can press Cmd+Z in the external app, but:

- Some apps may not support undo for AX-injected changes
- The undo target is not obvious — was it the AX write or the clipboard paste fallback?
- There is no visual feedback in WriteAssist that a correction was applied

This creates anxiety when accepting corrections, especially for confident words where the suggestion may be wrong.

## Proposed Fix

After successfully applying a correction, show a brief "Undo" toast notification in the HUD (or as a small persistent overlay near the caret) for 3–5 seconds:

```
✓ "teh" → "the"   [Undo]
```

If the user taps "Undo" within the window, perform the reverse AX injection (re-insert the original word). This is feasible because `WritingIssue` already contains both `word` (original) and `correction` is passed to `applyCorrection`.

The toast should auto-dismiss after the timeout or on the next keystroke.

## Additional Context

This feature would also serve as confirmation feedback — users currently have no visual confirmation in WriteAssist that their correction was applied (the HUD simply disappears).
