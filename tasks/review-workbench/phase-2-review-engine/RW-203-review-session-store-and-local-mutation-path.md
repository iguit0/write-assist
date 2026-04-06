# RW-203 — Build `ReviewSessionStore` and the one true local mutation path

## Phase
Phase 2 — Review engine

## Owner
Review engine agent

## Goal
Create the document-centric store that owns review state, analysis lifecycle, selection state, and local text mutation.

## In scope
Add:
- `Sources/ReviewDomain/ReviewSessionStore.swift`

## Required responsibilities
The store must own:
- current `ReviewDocument`
- current `ReviewAnalysisState`
- selected issue/paragraph/sentence IDs
- selected editor range
- analysis task cancellation/generation state
- the only local mutation API

## Required APIs
Include at least:
- `replaceText(_:source:trigger:autoReview:)`
- `requestReview(trigger:)`
- `selectIssue(id:)`
- `selectParagraph(id:)`
- `selectSentence(id:)`
- `applyReplacement(range:replacement:trigger:)`
- local deterministic apply/ignore helpers as needed for Phase 3

## Required behavior
- Increment `document.revision` on every real document mutation.
- Reject stale analysis results by revision and/or generation.
- Do not route local document edits through `CorrectionApplicator`.
- Keep review-window mutations local to the review document.

## Out of scope
- No app startup ownership
- No AI rewrite store

## Dependencies
- RW-001
- RW-201
- RW-202

## Acceptance criteria
- [ ] `ReviewSessionStore` compiles.
- [ ] Review requests can be cancelled safely.
- [ ] Stale review results are dropped by `documentRevision` and/or generation.
- [ ] All local document edits go through one mutation path.
- [ ] The store is independent from `GlobalInputMonitor` and `DocumentViewModel`.

## Coordination notes
- This is the document mutation authority for the new product path.
- UI and rewrite agents must not invent alternate mutation flows.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
