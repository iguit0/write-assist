# RW-001 — Freeze review domain contracts

## Phase
Phase 0 — Foundation

## Owner
Review domain / architecture agent

## Goal
Create the core review-domain contracts that every other agent can build against without inventing competing shapes.

## In scope
Add these files:
- `Sources/ReviewDomain/ReviewDocument.swift`
- `Sources/ReviewDomain/ReviewAnalysisSnapshot.swift`
- `Sources/ReviewDomain/ReviewPreferencesSnapshot.swift`

## Required contracts

### `ReviewDocument`
- `id: UUID`
- `text: String`
- `source: ReviewDocumentSource`
- `revision: Int`
- `updatedAt: Date`

### `ReviewDocumentSource`
- `.manual`
- `.paste`
- `.importedSelection(ImportedSelectionMetadata)`

### `ImportedSelectionMetadata`
- `appName: String?`
- `bundleIdentifier: String?`
- `importedAt: Date`

### `ReviewAnalysisSnapshot`
- `documentID: UUID`
- `documentRevision: Int`
- `analyzedAt: Date`
- `analysis: NLAnalysis`
- `issues: [WritingIssue]`
- `metrics: DocumentMetrics`
- `paragraphs: [ReviewParagraphSnapshot]`

### `ReviewParagraphSnapshot`
- `id: String`
- `range: NSRange`
- `text: String`
- `sentences: [ReviewSentenceSnapshot]`
- `issueIDs: [String]`

### `ReviewSentenceSnapshot`
- `id: String`
- `range: NSRange`
- `text: String`
- `issueIDs: [String]`

### `ReviewPreferencesSnapshot`
- `formality: FormalityLevel`
- `audience: AudienceLevel`
- `disabledRules: Set<String>`

## Required invariants
- Paragraph and sentence IDs must be range-based: `"\(range.location):\(range.length)"`
- These types must be `Sendable` where appropriate.
- These files must not import UI-only dependencies.

## Out of scope
- No engine implementation
- No store implementation
- No UI
- No startup wiring

## Dependencies
None

## Acceptance criteria
- [ ] All three files compile.
- [ ] Types match the shapes above.
- [ ] IDs are clearly documented as range-based.
- [ ] The new contracts do not depend on legacy inline-monitor types.

## Coordination notes
- Do not modify `DocumentViewModel.swift`.
- Do not change `WritingIssue.id` in this ticket.
- If a contract change feels necessary, stop and escalate instead of improvising.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
