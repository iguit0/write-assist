# WriteAssist Review Workbench — Orchestrated Implementation Plan

## Purpose

This is the execution plan for the product pivot defined in:
- `tasks/prd-writeassist-review-workbench.md`
- `docs/architecture/review-workbench-target-architecture.md`
- `docs/plans/review-workbench-migration-plan.md`

This document is optimized for **parallel agent execution**.

The core rule is simple:

> Build the new review-workbench path beside the legacy inline path, switch startup to the new path early, and retire the old system only after the new one is usable.

Do **not** spend cycles perfecting the old Grammarly-like inline stack.

---

## North star

WriteAssist becomes:
- a **main review window**
- for **non-native English speakers**
- with **deterministic review first**
- and **local-first AI rewrite second**
- plus an optional one-shot **Review Selection** bridge from other apps

WriteAssist is **not** optimizing for:
- continuous system-wide monitoring
- always-on floating HUDs
- permanent AX polling as the product center

---

## Execution strategy

### Delivery model
Use a **strangler migration**:
1. freeze contracts
2. add the new workbench stack
3. switch default startup to the workbench stack
4. keep legacy inline code compiling behind mode gates
5. remove or quarantine legacy code later

### Why this is the right approach
- minimizes merge conflicts in legacy god files
- lets multiple agents work in parallel in new directories
- keeps rollback simple
- avoids dragging legacy assumptions into the new product

---

## Global implementation rules

- One owner for each high-conflict file.
- New work goes into new folders first:
  - `Sources/ReviewDomain/`
  - `Sources/ReviewServices/`
  - `Sources/ReviewWindow/`
  - `Sources/Rewrite/`
  - `Sources/SystemIntegration/`
- UI must not mutate document text directly.
- Rewrite acceptance must go through one mutation path.
- Selection import must be one-shot; no hidden polling.
- No new feature work lands in legacy HUD / monitor / panel files unless it is a temporary compatibility patch.

---

## High-conflict files with single-owner rule

Exactly one agent/integrator owns each of these during the migration:
- `Sources/App/WriteAssistApp.swift`
- `Sources/StatusBarController.swift`
- `Sources/CloudAIService.swift`
- `Sources/SettingsPanel.swift`
- `Sources/PreferencesManager.swift` (if prefs expand)
- `Sources/WritingIssue.swift` (if identity contracts change)

No parallel edits here.

---

## Contracts to freeze before parallel work

These should land first and stay stable while the rest of the work happens.

### `Sources/ReviewDomain/ReviewDocument.swift`
```swift
struct ReviewDocument: Identifiable, Sendable, Equatable {
    let id: UUID
    var text: String
    var source: ReviewDocumentSource
    var revision: Int
    var updatedAt: Date
}

enum ReviewDocumentSource: Sendable, Equatable {
    case manual
    case paste
    case importedSelection(ImportedSelectionMetadata)
}

struct ImportedSelectionMetadata: Sendable, Equatable {
    let appName: String?
    let bundleIdentifier: String?
    let importedAt: Date
}
```

### `Sources/ReviewDomain/ReviewAnalysisSnapshot.swift`
```swift
struct ReviewAnalysisSnapshot: Sendable, Equatable {
    let documentID: UUID
    let documentRevision: Int
    let analyzedAt: Date
    let analysis: NLAnalysis
    let issues: [WritingIssue]
    let metrics: DocumentMetrics
    let paragraphs: [ReviewParagraphSnapshot]
}

struct ReviewParagraphSnapshot: Identifiable, Sendable, Equatable {
    let id: String
    let range: NSRange
    let text: String
    let sentences: [ReviewSentenceSnapshot]
    let issueIDs: [String]
}

struct ReviewSentenceSnapshot: Identifiable, Sendable, Equatable {
    let id: String
    let range: NSRange
    let text: String
    let issueIDs: [String]
}
```

### `Sources/ReviewDomain/ReviewPreferencesSnapshot.swift`
```swift
struct ReviewPreferencesSnapshot: Sendable, Equatable {
    let formality: FormalityLevel
    let audience: AudienceLevel
    let disabledRules: Set<String>
}
```

### `Sources/ReviewServices/ReviewEngine.swift`
```swift
protocol ReviewEngine: Sendable {
    func analyze(
        document: ReviewDocument,
        preferences: ReviewPreferencesSnapshot
    ) async -> ReviewAnalysisSnapshot
}
```

### `Sources/ReviewDomain/ReviewSessionStore.swift`
```swift
enum ReviewAnalysisState: Sendable, Equatable {
    case idle
    case analyzing(revision: Int)
    case ready(ReviewAnalysisSnapshot)
}

enum ReviewTrigger: Sendable, Equatable {
    case manualReview
    case editorChange
    case importedSelection
    case rewriteApplied
}
```

`ReviewSessionStore` must own:
- current `ReviewDocument`
- current analysis state
- selected issue/paragraph/sentence IDs
- selected editor range
- the only local document mutation path

### `Sources/Rewrite/*`
Freeze:
- `RewriteMode`
- `RewriteTarget`
- `RewriteRequest`
- `RewriteCandidate`
- `RewriteResult`
- `RewriteProviderPolicy`
- `RewriteEngine`
- `RewriteSessionStore`

### `Sources/SystemIntegration/*`
Freeze:
- `SelectionImporting`
- `ImportedSelection`
- `SelectionImportError`

### Shared invariants
- paragraph/sentence IDs must be range-based: `"\(range.location):\(range.length)"`
- stale work must be rejected by `documentRevision`
- all rewrite accept paths go through `ReviewSessionStore.applyReplacement(...)`

---

## Phase plan

## Phase 0 — Contract freeze and compile-safe seams

### Goal
Establish stable contracts so multiple agents can build in parallel without inventing conflicting shapes.

### Deliverables
- all contract files listed above
- placeholder implementations where needed
- `Sources/App/AppMode.swift` with:
  - `.legacyInline`
  - `.reviewWorkbenchHybrid`
  - `.reviewWorkbenchOnly`

### Parallelization
This phase is mostly serial. Get it in first.

### Blocking dependencies
None.

### Exit criteria
- new contract files compile
- other agents can build against them without touching legacy app startup

---

## Phase 1 — Main app shell and startup cutover scaffold

### Goal
Make the review window the primary app surface.

### Deliverables
- app opens a real review window
- menu bar becomes launcher-only
- legacy inline code still compiles, but is not the default experience

### Files to add
- `Sources/App/AppShellController.swift`
- `Sources/ReviewWindow/ReviewWorkbenchView.swift`
- `Sources/ReviewWindow/ReviewWorkbenchLayout.swift`

### Files to change
- `Sources/App/WriteAssistApp.swift`
- `Sources/StatusBarController.swift`

### Parallelizable work
- shell controller + startup wiring
- review window scaffold
- launcher-only menu bar mode

### Blocking dependencies
- Phase 0 contracts

### Merge order
1. `AppShellController`
2. launcher-mode API on `StatusBarController`
3. `WriteAssistApp` cutover to workbench scene
4. skeleton review window

### Exit criteria
- app launches to a review window
- menu bar opens/focuses the review window
- no default startup dependency on `GlobalInputMonitor` / `SelectionMonitor`

---

## Phase 2 — Deterministic review engine extraction

### Goal
Extract the real review pipeline out of `DocumentViewModel` and make it document-centric.

### Deliverables
- `DeterministicReviewEngine`
- paragraph/sentence grouping
- `ReviewSessionStore`
- explicit review action against the current document text

### Files to add
- `Sources/ReviewServices/DeterministicReviewEngine.swift`
- `Sources/ReviewServices/ReviewGrouping.swift`
- `Sources/ReviewDomain/ReviewSessionStore.swift`

### Files to reuse
- `Sources/SpellCheckService.swift`
- `Sources/NLAnalysisService.swift`
- `Sources/RuleEngine.swift`
- `Sources/WritingRules/*`
- `Sources/DocumentMetrics.swift`
- `Sources/WritingIssue.swift`

### Parallelizable work
- engine orchestration
- grouping logic
- store + cancellation/revision logic
- tests

### Blocking dependencies
- Phase 1 shell/store path available
- Phase 0 contracts frozen

### Merge order
1. engine
2. grouping
3. store
4. tests
5. workbench UI wiring

### Exit criteria
- the app can review manual/pasted text without `GlobalInputMonitor`
- results are grouped by paragraph/sentence
- stale review results are dropped via `documentRevision`

---

## Phase 3 — Review workbench UI

### Goal
Make deterministic review useful before touching AI or system integration.

### Deliverables
- editable review editor
- grouped paragraph/sentence/issue sidebar
- issue inspector
- local deterministic apply/ignore actions
- selection sync between editor and results

### Files to add
- `Sources/ReviewWindow/ReviewEditorView.swift`
- `Sources/ReviewWindow/ParagraphReviewList.swift`
- `Sources/ReviewWindow/ParagraphReviewCard.swift`
- `Sources/ReviewWindow/ReviewInspectorView.swift`
- `Sources/ReviewWindow/IssueSuggestionList.swift`

### Files to leave alone initially
- `Sources/ContentView.swift`
- `Sources/IssuesListView.swift`
- `Sources/IssueSidebarCard.swift`
- `Sources/HighlightedTextView.swift`

Use them as reference only. Don’t mutate them into the new product surface.

### Parallelizable work
- editor bridge
- sidebar/grouped results UI
- inspector UI
- overall layout integration

### Blocking dependencies
- Phase 2 store and grouped snapshots

### Merge order
1. editor
2. grouped list
3. inspector
4. integrated workbench layout

### Exit criteria
- user can paste/type text
- run review
- click issue
- see relevant range selected/highlighted
- apply deterministic suggestions locally

---

## Phase 4 — Explicit rewrite flow, local-first

### Goal
Ship the actual hero feature: rewrite and compare.

### Deliverables
- rewrite contracts and store
- local-first rewrite engine
- sentence rewrite first
- compare UI
- accept/reject into local document
- review reruns after accept

### Files to add
- `Sources/Rewrite/RewriteMode.swift`
- `Sources/Rewrite/RewriteRequest.swift`
- `Sources/Rewrite/RewriteCandidate.swift`
- `Sources/Rewrite/RewriteEngine.swift`
- `Sources/Rewrite/LocalFirstRewriteEngine.swift`
- `Sources/Rewrite/RewriteSessionStore.swift`
- `Sources/Rewrite/RewriteTargetResolver.swift`
- `Sources/ReviewWindow/RewriteCompareView.swift`
- `Sources/ReviewWindow/RewriteToolbar.swift`

### Files to change
- `Sources/CloudAIService.swift`
- `Sources/OllamaService.swift`
- `Sources/AIPromptTemplates.swift`
- `Sources/SettingsPanel.swift`

### Parallelizable work
- rewrite service layer
- compare UI
- target resolver
- settings/provider surfacing

### Blocking dependencies
- Phase 3 selection/editor flow
- Phase 0 rewrite contracts
- one mutation path in `ReviewSessionStore`

### Merge order
1. rewrite contracts + store
2. local-first rewrite engine
3. compare UI
4. accept/reject integration
5. paragraph rewrite after sentence rewrite is stable

### Exit criteria
- user can select sentence
- request rewrite
- compare original vs candidate
- accept into document
- review reruns cleanly

---

## Phase 5 — One-shot “Review Selection” integration

### Goal
Keep convenience, drop ambient complexity.

### Deliverables
- one-shot selection import service
- launcher menu bar action for Review Selection
- import into workbench with auto-review
- user-facing failure notices

### Files to add
- `Sources/SystemIntegration/SelectionImporting.swift`
- `Sources/SystemIntegration/SelectionImportService.swift`
- `Sources/SystemIntegration/SelectionImportError.swift`

### Files to change
- `Sources/App/AppShellController.swift`
- `Sources/StatusBarController.swift`
- `Sources/AXHelper.swift` (additive helpers only, if needed)

### Explicit anti-goals
Do **not** reuse as dependencies:
- `Sources/SelectionMonitor.swift`
- `Sources/GlobalInputMonitor.swift`
- `Sources/ExternalSpellChecker.swift`

### Parallelizable work
- import service
- launcher action
- error/notice UI
- tests

### Blocking dependencies
- Phase 1 launcher shell
- Phase 2 text replacement/review path
- Phase 3 workbench window

### Merge order
1. import service
2. shell integration
3. launcher action
4. failure handling UI

### Exit criteria
- user can trigger Review Selection
- imported selection appears in the review window
- review runs without permanent background monitoring

---

## Phase 6 — Legacy quarantine and default-mode cleanup

### Goal
Make the review workbench the real product, not the sidecar.

### Deliverables
- default app mode becomes `reviewWorkbenchOnly`
- legacy inline path behind explicit mode gate only
- docs/README updated
- legacy inline files marked quarantined/non-primary

### Files to change or quarantine
- `Sources/GlobalInputMonitor.swift`
- `Sources/SelectionMonitor.swift`
- `Sources/ExternalSpellChecker.swift`
- `Sources/ErrorHUDPanel.swift`
- `Sources/SelectionSuggestionPanel.swift`
- `Sources/SelectionSuggestionView.swift`
- `Sources/UndoToastPanel.swift`
- `Sources/GlobalKeyEventRouter.swift`
- large AX writeback parts of `Sources/CorrectionApplicator.swift`
- `Sources/StatusBarController.swift`
- `Sources/App/WriteAssistApp.swift`

### Parallelizable work
- mode gating
- docs cleanup
- deprecation comments / quarantine
- optional physical deletion later

### Blocking dependencies
- Phases 1–5 all usable

### Merge order
1. mode gating
2. default startup cleanup
3. docs/README
4. optional deletions after stabilization

### Exit criteria
- app is useful with no always-on inline subsystems active
- new work lands only in workbench paths

---

## Agent workstreams

## Workstream 1 — App shell / window / launcher

### Owns
- `Sources/App/WriteAssistApp.swift`
- `Sources/App/AppShellController.swift`
- `Sources/StatusBarController.swift` (launcher mode only)
- `Sources/ReviewWindow/ReviewWorkbenchView.swift`
- `Sources/ReviewWindow/ReviewWorkbenchLayout.swift`

### Does not touch
- `CloudAIService.swift`
- review engine internals
- AX monitoring files except through launcher API integration

### Mission
- real startup cutover
- real review window
- launcher-only menu bar behavior

---

## Workstream 2 — Review domain / deterministic engine

### Owns
- `Sources/ReviewDomain/*`
- `Sources/ReviewServices/*`

### May touch carefully
- `Sources/DocumentMetrics.swift`
- `Sources/RuleEngine.swift`

### Does not touch
- app startup
- menu bar
- AI settings UI

### Mission
- review document/state model
- deterministic analysis engine
- paragraph/sentence grouping
- apply/ignore local mutation path

---

## Workstream 3 — Review workbench UI

### Owns
- `Sources/ReviewWindow/ReviewEditorView.swift`
- `Sources/ReviewWindow/ParagraphReviewList.swift`
- `Sources/ReviewWindow/ParagraphReviewCard.swift`
- `Sources/ReviewWindow/ReviewInspectorView.swift`
- `Sources/ReviewWindow/IssueSuggestionList.swift`
- `Sources/ReviewWindow/RewriteCompareView.swift` (once rewrite contracts exist)

### Does not touch
- engine internals
- app startup
- legacy issue list/popover files

### Mission
- editor
- grouped result navigation
- inspector
- compare UI

---

## Workstream 4 — Rewrite engine / provider layer

### Owns
- `Sources/Rewrite/*`
- `Sources/CloudAIService.swift`
- `Sources/OllamaService.swift`
- `Sources/AIPromptTemplates.swift`
- `Sources/SettingsPanel.swift`

### Does not touch
- `WriteAssistApp.swift`
- `StatusBarController.swift`
- review grouping files

### Mission
- local-first rewrite path
- request-scoped AI API
- fallback policy
- rewrite store
- settings/provider surfacing

---

## Workstream 5 — System integration

### Owns
- `Sources/SystemIntegration/*`

### May touch carefully
- `Sources/AXHelper.swift` (additive helpers only)

### Does not touch
- `SelectionMonitor.swift`
- `GlobalInputMonitor.swift`
- `ExternalSpellChecker.swift`
- `StatusBarController.swift` directly unless coordinated with shell owner

### Mission
- one-shot Review Selection import
- secure-context/error mapping
- import metadata

---

## Workstream 6 — Legacy retirement / docs / tests

### Owns
- `Tests/WriteAssistTests/*`
- `README.md`
- `docs/*`
- quarantining/deprecation docs for legacy files

### Mission
- contract tests
- review/rewrite tests
- import failure tests
- docs cleanup
- legacy notices

---

## Merge protocol

### Global order
1. contracts
2. shell scaffold
3. review engine
4. workbench UI
5. rewrite engine
6. compare UI integration
7. selection import
8. launcher integration
9. legacy quarantine
10. docs/tests sweep

### PR boundary rule
Each agent/PR should do one of:
- contracts only
- shell only
- review engine only
- UI only
- rewrite only
- system integration only
- docs/tests only

Do not mix shell + AI + AX + UI in one branch.

---

## Biggest coordination risks and how to avoid them

## Risk 1 — `WriteAssistApp.swift` and `StatusBarController.swift` become merge hell
**Fix:** one integrator owns startup and launcher behavior.

## Risk 2 — paragraph/sentence IDs drift across engine/UI/rewrite code
**Fix:** freeze range-based IDs up front. No alternate schemes.

## Risk 3 — multiple mutation paths appear for document text
**Fix:** all accepts/edits route through `ReviewSessionStore.applyReplacement(...)`.

## Risk 4 — agents try to “reuse” old popover/HUD files and drag old assumptions into the new stack
**Fix:** new folders only. Copy useful code, don’t mutate old product surfaces into the new one.

## Risk 5 — selection import accidentally reintroduces permanent AX complexity
**Fix:** one-shot import service only. No polling, no background monitors.

## Risk 6 — `CloudAIService` stays globally throttled and blocks rewrite UX
**Fix:** rewrite workstream owns that file and moves it toward request-scoped APIs before more UI depends on it.

---

## Best first three implementation slices

## Slice 1 — Real workbench shell + manual text + deterministic review
This is the first slice. No debate.

### Must work
- app opens a main review window
- user can type/paste text
- user can run review
- grouped deterministic results show up

### Workstreams involved
- shell
- review engine
- minimal workbench UI

### Why first
This is the actual product pivot. Without this, nothing changed.

---

## Slice 2 — Grouped review UI + deterministic apply/dismiss

### Must work
- click issue
- highlight/select relevant range
- apply deterministic suggestion locally
- ignore issue locally
- rerun review cleanly

### Workstreams involved
- review engine
- workbench UI
- tests

### Why second
This makes the app useful even before AI.

---

## Slice 3 — Sentence rewrite compare + accept

### Must work
- request sentence rewrite
- compare original vs candidate
- accept into document
- rerun review

### Workstreams involved
- rewrite engine
- compare UI
- review store integration

### Why third
This is the hero feature. Review Selection import is only a bridge and should come after the core value is working.

---

## Recommended execution order if spawning agents now

1. **Integrator / shell agent**
   - contracts check
   - startup cutover scaffold
   - launcher-only menu bar mode

2. **Review engine agent**
   - `ReviewDomain/*`
   - `ReviewServices/*`
   - deterministic review path

3. **Workbench UI agent**
   - editor
   - grouped results
   - inspector

4. **Rewrite agent**
   - `Rewrite/*`
   - `CloudAIService` refactor
   - compare flow

5. **System integration agent**
   - `SystemIntegration/*`
   - one-shot selection import only

6. **Docs/tests agent**
   - tests per slice
   - README/docs sync
   - legacy quarantine notes

---

## Copy-paste agent briefs

## Agent brief — Shell / integrator
Build the primary review-window app shell. Own `Sources/App/WriteAssistApp.swift`, `Sources/App/AppShellController.swift`, and launcher-mode `Sources/StatusBarController.swift`. Do not touch rewrite/provider internals. Goal: app launches into a review window, menu bar becomes launcher only, legacy inline path is no longer the default startup path.

## Agent brief — Review engine
Build `Sources/ReviewDomain/*` and `Sources/ReviewServices/*`. Reuse `SpellCheckService`, `NLAnalysisService`, `RuleEngine`, `WritingRules`, and `DocumentMetrics`. Goal: document-centric deterministic review with paragraph/sentence grouping and revision-safe result delivery. Do not touch app startup or AI settings.

## Agent brief — Workbench UI
Build `Sources/ReviewWindow/*` for editor, grouped result list, inspector, and compare scaffolding. Consume frozen review/rewrite store contracts. Do not call AI services or mutate document text directly. All edits must route through store APIs.

## Agent brief — Rewrite engine
Own `Sources/Rewrite/*`, `Sources/CloudAIService.swift`, `Sources/OllamaService.swift`, `Sources/AIPromptTemplates.swift`, and rewrite-related settings work. Goal: local-first sentence rewrite with optional cloud fallback and request-scoped AI calls. Do not touch shell startup files.

## Agent brief — System integration
Build `Sources/SystemIntegration/*` for one-shot Review Selection import. Reuse `AXHelper` only through additive helpers. Do not depend on `SelectionMonitor`, `GlobalInputMonitor`, or `ExternalSpellChecker`.

## Agent brief — Docs/tests
Own tests and docs updates per slice. Add tests for revision safety, deterministic review grouping, rewrite accept flow, and selection import errors. Keep README and architecture docs aligned with the workbench direction.

---

## Success condition for the migration

The migration is succeeding when:
- the app is useful with **manual paste/write review alone**
- rewrite is explicit and local-first
- Review Selection is convenient but optional
- startup no longer depends on always-on monitoring
- the legacy inline stack is clearly secondary or removed
