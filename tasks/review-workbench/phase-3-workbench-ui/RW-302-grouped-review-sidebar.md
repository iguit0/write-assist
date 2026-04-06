# RW-302 — Build grouped paragraph/sentence review sidebar

## Phase
Phase 3 — Workbench UI

## Owner
Workbench UI agent

## Goal
Render review results structurally by paragraph and sentence instead of as a flat legacy issue list.

## In scope
Add:
- `Sources/ReviewWindow/ParagraphReviewList.swift`
- `Sources/ReviewWindow/ParagraphReviewCard.swift`

## Required behavior
- Render paragraphs from `ReviewAnalysisSnapshot.paragraphs`.
- Show issue counts and sentence-level issue grouping.
- Allow selection callbacks for paragraphs, sentences, and issues.
- Keep these views dumb: render state, trigger closures.

## Out of scope
- No direct engine calls
- No direct AI calls
- No mutation of `IssuesListView.swift`

## Dependencies
- RW-202
- RW-203
- RW-301

## Acceptance criteria
- [ ] The grouped sidebar compiles and renders.
- [ ] Paragraphs and sentences are shown from grouped snapshot data.
- [ ] Selecting an item can drive store selection state.
- [ ] The implementation does not depend on legacy flat issue list UI.

## Coordination notes
- Do not patch `IssuesListView.swift` into this.
- Treat the grouped snapshot contract as the source of truth.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
