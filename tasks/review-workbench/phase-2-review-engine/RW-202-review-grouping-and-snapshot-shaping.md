# RW-202 — Group review results by paragraph and sentence

## Phase
Phase 2 — Review engine

## Owner
Review engine agent

## Goal
Transform deterministic analysis output into paragraph/sentence-grouped snapshot data the workbench UI can consume directly.

## In scope
Add:
- `Sources/ReviewServices/ReviewGrouping.swift`

## Required grouping behavior
- Derive paragraph ranges from the document text.
- Bucket `analysis.sentenceRanges` into paragraphs.
- Bucket `WritingIssue` ranges into paragraph and sentence groups.
- Emit stable range-based IDs.
- Preserve `issueIDs` references instead of duplicating issue models.

## Required invariants
- Each paragraph/sentence ID must be `"\(range.location):\(range.length)"`.
- Every `issueID` referenced in grouped nodes must exist in the snapshot issue array.
- Grouping must be valid for the current `documentRevision` only.

## Out of scope
- No UI rendering
- No selection state
- No rewrite target resolution

## Dependencies
- RW-001
- RW-201

## Acceptance criteria
- [ ] Grouping helper compiles.
- [ ] Paragraph and sentence grouping is deterministic.
- [ ] Range-based IDs are used consistently.
- [ ] Grouped output is shaped for UI consumption without extra text searching.

## Coordination notes
- This ticket freezes the paragraph/sentence identity scheme. Do not improvise another one later.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
