# RW-401 — Implement rewrite session store and request lifecycle

## Phase
Phase 4 — Rewrite

## Owner
Rewrite engine agent

## Goal
Move from frozen rewrite contracts to a real rewrite session store that the compare UI can bind to.

## In scope
Add:
- `Sources/Rewrite/RewriteSessionStore.swift`
- `Sources/Rewrite/RewriteTargetResolver.swift`

If the frozen rewrite contract files from RW-002 were placeholders, finish them here.

## Required behavior
- Own active rewrite request state.
- Own loading/error/success state.
- Own selected candidate state.
- Resolve rewrite targets in this order:
  1. selected sentence
  2. selected paragraph
  3. explicit editor selection
- Reject stale rewrite results by `documentRevision`.

## Required integration
Provide an accept flow that ultimately applies changes through:
- `ReviewSessionStore.applyReplacement(range:replacement:trigger:)`

## Out of scope
- No provider implementation details here if they belong in RW-402.
- No final compare UI implementation here if it belongs in RW-403.

## Dependencies
- RW-002
- RW-203
- RW-301

## Acceptance criteria
- [ ] `RewriteSessionStore` compiles and owns rewrite request lifecycle.
- [ ] Rewrite target resolution works against review-store selection state.
- [ ] Stale rewrite results are dropped safely.
- [ ] Accept flow is designed around the single review-store mutation path.

## Coordination notes
- Do not let UI files mutate the review document directly.
- This ticket locks the rewrite state model for RW-403.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
