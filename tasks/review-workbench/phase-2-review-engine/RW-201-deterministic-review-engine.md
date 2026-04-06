# RW-201 — Build `DeterministicReviewEngine`

## Phase
Phase 2 — Review engine

## Owner
Review engine agent

## Goal
Extract a document-centric deterministic review pipeline using the existing spell/NLP/rule services.

## In scope
Add:
- `Sources/ReviewServices/DeterministicReviewEngine.swift`

Reuse:
- `Sources/SpellCheckService.swift`
- `Sources/NLAnalysisService.swift`
- `Sources/RuleEngine.swift`
- `Sources/WritingRules/*`
- `Sources/DocumentMetrics.swift`

## Required execution order
For the current document text:
1. local spell/grammar pass
2. `NLAnalysisService.analyze(...)`
3. `RuleRegistry.runAll(...)`
4. metric build
5. snapshot construction

## Required behavior
- The engine must accept a `ReviewDocument` and `ReviewPreferencesSnapshot`.
- The engine must not read `PreferencesManager.shared` directly from background execution.
- The engine must return `ReviewAnalysisSnapshot`.
- The engine must remain deterministic and local-only.

## Out of scope
- No grouped paragraph/sentence shaping here if that causes coupling — that belongs in RW-202.
- No UI state.
- No rewrite flow.

## Dependencies
- RW-001
- RW-003

## Acceptance criteria
- [ ] `DeterministicReviewEngine` compiles and runs off the new contracts.
- [ ] It reuses the existing deterministic services.
- [ ] It can analyze full review text rather than a hidden rolling buffer.
- [ ] It does not depend on `DocumentViewModel`.

## Coordination notes
- Do not change `DocumentViewModel.runCheck(...)` unless strictly necessary.
- Additive extraction only.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
