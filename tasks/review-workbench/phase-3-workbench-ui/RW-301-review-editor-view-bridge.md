# RW-301 — Build the editable review editor bridge

## Phase
Phase 3 — Workbench UI

## Owner
Workbench UI agent

## Goal
Create the main editable text surface for the review window.

## In scope
Add:
- `Sources/ReviewWindow/ReviewEditorView.swift`

## Required behavior
- Back the editor with `NSTextView` or equivalent AppKit editor.
- Support editable text.
- Support selection callbacks.
- Support issue highlighting from current review issues.
- Support synchronization with `ReviewSessionStore`.

## Required store integration
The editor must not mutate text directly in arbitrary ways.
It should communicate changes and selection through store-facing APIs/callbacks.

## Out of scope
- No grouped sidebar UI
- No rewrite compare UI
- No legacy `HighlightedTextView` mutation-in-place

## Dependencies
- RW-102
- RW-203

## Acceptance criteria
- [ ] The review editor compiles and renders in the workbench.
- [ ] Text can be typed/pasted.
- [ ] Selection changes can be observed.
- [ ] Issue highlighting can be rendered from deterministic review results.
- [ ] The implementation does not depend on floating HUD or popover logic.

## Coordination notes
- Do not mutate `HighlightedTextView.swift` into the main editor.
- New file, new bridge.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
