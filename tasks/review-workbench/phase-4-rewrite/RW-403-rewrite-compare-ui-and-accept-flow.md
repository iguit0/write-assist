# RW-403 — Build rewrite compare UI and wire accept/reject into the document

## Phase
Phase 4 — Rewrite

## Owner
Workbench UI agent with rewrite-agent coordination

## Goal
Ship the first user-visible rewrite flow: sentence rewrite, compare, accept.

## In scope
Add:
- `Sources/ReviewWindow/RewriteCompareView.swift`
- `Sources/ReviewWindow/RewriteToolbar.swift`

## Required behavior
- Show original vs rewritten candidate.
- Show provider/model info.
- Allow accept / reject / regenerate.
- Accept must update the review document through `ReviewSessionStore.applyReplacement(...)`.
- Trigger deterministic re-review after accept.

## Recommended scope
Sentence rewrite first.
Paragraph rewrite can come after the sentence flow is stable.

## Out of scope
- No system integration / selection import
- No legacy floating rewrite panels

## Dependencies
- RW-401
- RW-402
- RW-303

## Acceptance criteria
- [ ] Compare UI compiles and renders.
- [ ] A user can request a sentence rewrite and see at least one candidate.
- [ ] Accept updates the local document via the review store.
- [ ] Review reruns after acceptance.
- [ ] Reject does not mutate the document.

## Coordination notes
- The compare pane is a stable review-window surface, not a floating panel.
- Keep mutation flow centralized.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
