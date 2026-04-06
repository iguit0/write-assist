# WriteAssist Target Architecture

## Purpose

This document replaces the implicit “system-wide inline assistant” direction with the intended product shape:

**WriteAssist is a review-and-rewrite workbench for non-native English speakers.**

The app may keep a menu bar entry and a deliberate “Review Selection” import path, but the primary product is a focused review window — not always-on Grammarly-style monitoring.

---

## Product modes

## 1. Primary mode: Review Workbench
The default experience.

User flow:
1. write or paste text into WriteAssist
2. run or refresh review
3. inspect issues by paragraph/sentence
4. request rewrite actions explicitly
5. compare original vs rewritten output
6. accept or reject changes into the review document

## 2. Secondary mode: Review Selection
A convenience bridge from another app.

User flow:
1. trigger “Review Selection” from menu bar or shortcut
2. import selected text once
3. open/focus the review window
4. continue the same review workflow there

## 3. Legacy mode: Inline system-wide assistant
This is no longer the target product.

Existing code may remain temporarily while migration happens, but it is not the architecture to optimize around.

---

## Architectural principles

### Explicit over ambient
Review and rewrite are user-initiated actions, not background behavior.

### Local-first AI
Use local models by default for rewrite/explanation workflows. Cloud fallback is optional.

### Deterministic review first, AI second
- deterministic pipeline = always available review baseline
- AI pipeline = on-demand rewrite / explanation / tone adjustment

### Document-centric state
The app should own a review document, not a hidden rolling typing buffer.

### Paragraph and sentence as first-class units
The UX should help users improve structure and flow, not just fix isolated tokens.

---

## Target top-level module layout

## App shell
Responsible for window lifecycle, menu bar launcher behavior, and optional selection import entry points.

Suggested responsibilities:
- create/focus the main review window
- expose menu bar actions
- route imported selection text into the review session
- avoid owning review logic directly

### Likely types
- `AppShellController`
- `ReviewWindowController` or SwiftUI scene coordinator
- `SelectionImportService` (one-shot, not continuous monitor)

---

## Review domain
Owns the current text document and analysis output.

### Suggested model shape
```swift
struct ReviewDocument {
    var text: String
    var paragraphs: [ReviewParagraph]
}

struct ReviewParagraph: Identifiable {
    let id: UUID
    var text: String
    var sentenceRanges: [Range<String.Index>]
}

struct ReviewAnalysis {
    var issues: [WritingIssue]
    var metrics: DocumentMetrics
    var paragraphSummaries: [ParagraphSummary]
}

struct ParagraphSummary: Identifiable {
    let id: UUID
    let paragraphID: UUID
    let issues: [WritingIssue]
}
```

### Suggested store
```swift
@Observable
final class ReviewSessionStore {
    var documentText: String = ""
    var analysis: ReviewAnalysis?
    var selectedParagraphID: UUID?
    var selectedIssueID: String?
    var isAnalyzing = false
}
```

This replaces the current “everything in `DocumentViewModel`” shape.

---

## Deterministic review engine
Responsible for local analysis and issue generation.

### Suggested responsibilities
- build `NLAnalysis`
- run deterministic rule engine
- run local spell/grammar checks
- produce grouped output for UI consumption
- avoid owning UI state

### Suggested protocol
```swift
protocol ReviewEngine {
    func analyze(text: String, preferences: ReviewPreferences) async -> ReviewAnalysis
}
```

### Reuse from current codebase
Keep and wrap:
- `SpellCheckService`
- `NLAnalysisService`
- `RuleEngine`
- `WritingRules/*`
- `DocumentMetrics`
- `WritingIssue`

### Required refactors
- move `runCheck` logic out of `DocumentViewModel`
- stop mixing live text editing state with analyzed result state
- introduce a shared preprocessed text snapshot for phrase-based rules

---

## Rewrite engine
Responsible for on-demand AI-assisted rewriting and explanation.

### Suggested responsibilities
- sentence rewrite
- paragraph rewrite
- explanation of awkward or flagged text
- compare candidates before application
- respect local-first provider policy

### Suggested protocol
```swift
protocol RewriteEngine {
    func rewriteSentence(_ text: String, mode: RewriteMode) async throws -> RewriteResult
    func rewriteParagraph(_ text: String, mode: RewriteMode) async throws -> RewriteResult
    func explain(_ text: String, context: String?) async throws -> String
}
```

### Suggested store
```swift
@Observable
final class RewriteSessionStore {
    var target: RewriteTarget?
    var mode: RewriteMode?
    var candidates: [RewriteCandidate] = []
    var isRewriting = false
    var activeProvider: AIProvider?
}
```

### Reuse from current codebase
Refactor and keep:
- `CloudAIService`
- `OllamaService`
- `AIPromptTemplates`
- settings/preferences for providers and models

### Required refactors
- split scheduling/backpressure from the current singleton UI state
- make provider selection explicit per rewrite request
- stop treating AI as ambient inline behavior

---

## UI composition

## Main regions
The review window should have stable, review-oriented surfaces:

1. **Input editor**
   - where text is written or pasted
2. **Review results sidebar / outline**
   - issues grouped by paragraph/sentence/category
3. **Context panel**
   - explanation of selected issue, paragraph details, metrics
4. **Rewrite compare panel**
   - original vs rewritten candidate, accept/reject actions

## Important UI rule
Inline floating panels are not the primary interaction model anymore.

Use stable window UI first. Temporary overlays are secondary and optional.

---

## Menu bar role

Menu bar remains, but as a launcher and convenience entry point only.

Allowed responsibilities:
- open/focus review window
- trigger Review Selection import
- quick provider/status indicator if needed

Not allowed as primary product shell:
- main review UX
- issue browsing
- paragraph rewrite workflow
- continuous inline correction orchestration

---

## Accessibility / system integration strategy

### Keep
- one-shot selected text import if reliable
- optional replace-back later, after review workbench is stable

### Avoid as core architecture
- permanent selection polling
- permanent global typing capture
- inline HUD positioning as primary UX
- AX writes in the hottest review path

### Why
This product does not need the complexity budget of a full ambient writing assistant.

---

## Current file mapping

## Keep largely as core domain/services
- `Sources/SpellCheckService.swift`
- `Sources/NLAnalysisService.swift`
- `Sources/RuleEngine.swift`
- `Sources/WritingRules/*`
- `Sources/WritingIssue.swift`
- `Sources/DocumentMetrics.swift`
- `Sources/PreferencesManager.swift`
- `Sources/PersonalDictionary.swift`
- `Sources/IgnoreRulesStore.swift`
- `Sources/CloudAIService.swift`
- `Sources/OllamaService.swift`
- `Sources/AIPromptTemplates.swift`

## Keep but reshape for the new app shell/UI
- `Sources/ContentView.swift`
- `Sources/IssuesListView.swift`
- `Sources/IssueSidebarCard.swift`
- `Sources/HighlightedTextView.swift`
- `Sources/ToolsPanel.swift`
- `Sources/SettingsPanel.swift`
- `Sources/WritingStatsView.swift`

## Refactor heavily
- `Sources/DocumentViewModel.swift`
  - split into review store + analysis engine + rewrite store
- `Sources/StatusBarController.swift`
  - shrink to launcher/import responsibilities only
- `Sources/CloudAIService.swift`
  - move request scheduling/policy into explicit rewrite-oriented services

## Legacy / retire from primary path
- `Sources/GlobalInputMonitor.swift`
- `Sources/SelectionMonitor.swift`
- `Sources/ExternalSpellChecker.swift`
- `Sources/ErrorHUDPanel.swift`
- `Sources/SelectionSuggestionPanel.swift`
- `Sources/SelectionSuggestionView.swift`
- `Sources/UndoToastPanel.swift`
- `Sources/GlobalKeyEventRouter.swift`
- large parts of `Sources/CorrectionApplicator.swift`
- AX-heavy floating panel orchestration paths

---

## State ownership rules

### ReviewSessionStore owns
- review document text
- selected issue / paragraph
- current deterministic analysis snapshot
- analysis lifecycle state

### RewriteSessionStore owns
- rewrite target
- rewrite mode
- rewrite candidates
- rewrite lifecycle state
- selected provider/model metadata for the request

### App shell owns
- window focus/opening
- menu bar lifecycle
- explicit selection import entry point

No single object should own all three concerns.

---

## Performance implications of the target architecture

The new architecture intentionally improves performance by removing the need for:
- per-keystroke full review passes on a hidden global buffer
- permanent selection polling as a core feature
- duplicated AX/HUD paths
- always-on overlay coordination

The heavy work becomes acceptable because it is attached to explicit review actions rather than ambient background behavior.

---

## Migration rule

**Do not try to perfect the legacy inline architecture first.**

Build the review-workbench path beside it, make that the default product, then retire legacy inline flows incrementally.
