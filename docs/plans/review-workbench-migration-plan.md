# WriteAssist Review Workbench Migration Plan

## Goal

Move WriteAssist from a system-wide inline assistant architecture to a review-first, local-first rewrite workbench without trying to perfect the legacy inline path.

This plan is intentionally tied to the current file layout.

---

## Strategic rule

Build the new product path beside the old one.
Do **not** keep deepening the current inline/HUD/AX stack.

Migration order:
1. establish docs as source of truth
2. create new review-first app shell
3. extract deterministic review pipeline from legacy coordinator
4. add explicit rewrite workflow
5. shrink menu bar + selection import to convenience only
6. retire legacy inline stack

---

## Phase 0 — Source-of-truth reset

### Deliverables
- new PRD
- target architecture doc
- migration plan
- mark old MVP PRD as historical

### Files
- `tasks/prd-writeassist-review-workbench.md`
- `docs/architecture/review-workbench-target-architecture.md`
- `docs/plans/review-workbench-migration-plan.md`
- `tasks/prd-writeassist.md` (prepend superseded notice)

### Notes
This phase prevents more blind product drift.

---

## Phase 1 — Introduce the real primary app shell

## Goal
Make the main review window the primary product surface.

### Deliverables
- app launches/focuses a review window
- menu bar becomes launcher only
- existing inline subsystems can still compile, but are no longer the core UX

### Current files to change
- `Sources/App/WriteAssistApp.swift`
- `Sources/ContentView.swift`
- `Sources/StatusBarController.swift`

### New files to add
- `Sources/ReviewWindow/ReviewWorkbenchView.swift`
- `Sources/ReviewWindow/ReviewWorkbenchLayout.swift`
- `Sources/App/AppShellController.swift` or equivalent

### Refactor direction
- keep `StatusBarController`, but strip it down to:
  - open/focus window
  - optional Review Selection entry point
- stop centering product flow on popovers and floating panels

### Exit criteria
- user can open the app and immediately review text in a proper window
- menu bar is no longer the only meaningful UI shell

---

## Phase 2 — Extract review state from `DocumentViewModel`

## Goal
Stop using `DocumentViewModel` as the all-purpose coordinator.

### Current files to change
- `Sources/DocumentViewModel.swift`
- `Sources/DocumentMetrics.swift`
- `Sources/IssuesListView.swift`
- `Sources/HighlightedTextView.swift`
- `Sources/ContentView.swift`

### New files to add
- `Sources/ReviewDomain/ReviewSessionStore.swift`
- `Sources/ReviewDomain/ReviewAnalysis.swift`
- `Sources/ReviewDomain/ReviewDocument.swift`
- `Sources/ReviewServices/ReviewEngine.swift`

### Refactor direction
Move these concerns out of `DocumentViewModel`:
- deterministic review orchestration
- current analysis snapshot
- selected issue / paragraph state
- text editing state vs analyzed state

Keep/reuse:
- `SpellCheckService`
- `NLAnalysisService`
- `RuleEngine`
- `WritingRules/*`
- `DocumentMetrics`
- `WritingIssue`

### Exit criteria
- deterministic review can run without `GlobalInputMonitor`
- review state is document-centric, not hidden-buffer-centric

---

## Phase 3 — Rebuild the review UI around paragraphs and compare flows

## Goal
Replace issue-only flat review with paragraph/sentence-oriented inspection and rewrite acceptance.

### Current files to change
- `Sources/IssuesListView.swift`
- `Sources/IssueSidebarCard.swift`
- `Sources/HighlightedTextView.swift`
- `Sources/ToolsPanel.swift`

### New files to add
- `Sources/ReviewWindow/ParagraphReviewList.swift`
- `Sources/ReviewWindow/ParagraphReviewCard.swift`
- `Sources/ReviewWindow/RewriteCompareView.swift`
- `Sources/ReviewWindow/SelectedIssueDetailView.swift`

### Refactor direction
- keep the useful parts of `HighlightedTextView`
- stop designing primarily around “floating issue suggestions”
- group findings by paragraph/sentence in stable window UI

### Exit criteria
- user can inspect issues structurally
- user can compare rewrite candidates before applying them

---

## Phase 4 — Make rewriting explicit and local-first

## Goal
Turn rewrite into the hero feature, not passive inline correction.

### Current files to change
- `Sources/CloudAIService.swift`
- `Sources/OllamaService.swift`
- `Sources/AIPromptTemplates.swift`
- `Sources/SettingsPanel.swift`
- `Sources/TextSelectionSuggestionsPanel.swift`

### New files to add
- `Sources/Rewrite/RewriteSessionStore.swift`
- `Sources/Rewrite/RewriteEngine.swift`
- `Sources/Rewrite/RewriteMode.swift`
- `Sources/Rewrite/RewriteCandidate.swift`

### Refactor direction
- local-first provider selection
- explicit rewrite requests only
- split request scheduling from coarse singleton UI state
- support sentence and paragraph rewrite targets

### Exit criteria
- user can request rewrite actions from the review window
- local model path is first-class
- cloud is optional fallback, not the default assumption

---

## Phase 5 — Replace continuous system-wide monitoring with deliberate import

## Goal
Keep convenience, lose the ambient complexity.

### Current files to shrink or isolate
- `Sources/GlobalInputMonitor.swift`
- `Sources/SelectionMonitor.swift`
- `Sources/ExternalSpellChecker.swift`
- `Sources/ErrorHUDPanel.swift`
- `Sources/SelectionSuggestionPanel.swift`
- `Sources/SelectionSuggestionView.swift`
- `Sources/UndoToastPanel.swift`
- `Sources/GlobalKeyEventRouter.swift`
- `Sources/CorrectionApplicator.swift`
- `Sources/AXHelper.swift`

### New files to add
- `Sources/SystemIntegration/SelectionImportService.swift`
- optional `Sources/SystemIntegration/SelectionImportError.swift`

### Refactor direction
- replace permanent monitoring with one-shot “Review Selection” import
- keep minimal AX surface only where it serves that deliberate workflow
- do not carry over floating HUD architecture into the new product

### Exit criteria
- selection import works without permanent polling
- the app remains useful even if Accessibility integration is disabled

---

## Phase 6 — Retire legacy inline subsystems

## Goal
Delete or quarantine the old architecture once the review workbench is stable.

### Candidates for removal from the primary app path
- `Sources/ExternalSpellChecker.swift`
- `Sources/ErrorHUDPanel.swift`
- `Sources/SelectionSuggestionPanel.swift`
- `Sources/SelectionSuggestionView.swift`
- `Sources/UndoToastPanel.swift`
- `Sources/GlobalKeyEventRouter.swift`
- permanent-monitoring portions of `Sources/GlobalInputMonitor.swift`
- permanent-polling portions of `Sources/SelectionMonitor.swift`

### Exit criteria
- no core feature depends on always-on inline monitoring
- no new work is landing in legacy inline files except temporary bugfixes during migration

---

## Keep / Refactor / Retire matrix

## Keep
- `Sources/SpellCheckService.swift`
- `Sources/NLAnalysisService.swift`
- `Sources/RuleEngine.swift`
- `Sources/WritingRules/*`
- `Sources/WritingIssue.swift`
- `Sources/DocumentMetrics.swift`
- `Sources/PreferencesManager.swift`
- `Sources/PersonalDictionary.swift`
- `Sources/IgnoreRulesStore.swift`
- `Sources/OllamaService.swift`

## Refactor
- `Sources/DocumentViewModel.swift`
- `Sources/CloudAIService.swift`
- `Sources/ContentView.swift`
- `Sources/IssuesListView.swift`
- `Sources/IssueSidebarCard.swift`
- `Sources/HighlightedTextView.swift`
- `Sources/SettingsPanel.swift`
- `Sources/StatusBarController.swift`
- `Sources/TextSelectionSuggestionsPanel.swift`

## Retire from primary path
- `Sources/GlobalInputMonitor.swift`
- `Sources/SelectionMonitor.swift`
- `Sources/ExternalSpellChecker.swift`
- `Sources/ErrorHUDPanel.swift`
- `Sources/SelectionSuggestionPanel.swift`
- `Sources/SelectionSuggestionView.swift`
- `Sources/UndoToastPanel.swift`
- `Sources/GlobalKeyEventRouter.swift`
- large AX writeback flows in `Sources/CorrectionApplicator.swift`

---

## Testing and validation priorities

### Must keep green during migration
- `swift build`
- `swift test`
- `swiftlint`

### New test focus areas
- deterministic review pipeline against full review text
- paragraph/sentence grouping correctness
- rewrite acceptance into the review document
- local-first provider selection behavior
- selection import behavior without continuous monitoring

---

## Implementation rules for the migration

- No new product features should be added to floating HUD / inline panel architecture.
- Any new review or rewrite feature should target the review window first.
- Accessibility integration should be treated as optional convenience, not the heart of the app.
- Local-first rewrite support is part of the core product, not an add-on.
- If a refactor decision helps the legacy inline path but hurts the review-workbench path, prefer the review-workbench path.

---

## First concrete implementation slice after this doc set

Recommended first engineering slice:
1. add the new review workbench window
2. make menu bar open/focus that window
3. keep paste/manual text review working there
4. run deterministic full review on that document
5. leave legacy inline path compiling, but clearly secondary

That gets the product back onto the right rails fast.
