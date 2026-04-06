# RW-303 — Build issue inspector and deterministic local actions

## Phase
Phase 3 — Workbench UI

## Owner
Workbench UI agent

## Goal
Create the right-side issue inspector that shows details and lets the user apply deterministic suggestions or ignore issues locally.

## In scope
Add:
- `Sources/ReviewWindow/ReviewInspectorView.swift`
- `Sources/ReviewWindow/IssueSuggestionList.swift`

## Required behavior
- Show selected issue details:
  - issue type
  - message
  - suggestions
  - local apply button(s)
  - ignore/dismiss action
- Trigger local apply/ignore through `ReviewSessionStore`
- Sync with editor/range selection if applicable

## Out of scope
- No AI rewrite logic here
- No direct text mutation outside store APIs
- No reuse of `IssueSidebarCard.swift` as the main implementation

## Dependencies
- RW-203
- RW-301
- RW-302

## Acceptance criteria
- [ ] The inspector compiles and renders.
- [ ] A selected issue can show its suggestions.
- [ ] Applying a deterministic suggestion routes through `ReviewSessionStore`.
- [ ] Ignoring an issue routes through `ReviewSessionStore`.
- [ ] The document updates locally without `CorrectionApplicator`.

## Coordination notes
- Keep deterministic actions separate from AI rewrite actions.
- This ticket should leave room for `RewriteCompareView` to take over the compare panel later.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
