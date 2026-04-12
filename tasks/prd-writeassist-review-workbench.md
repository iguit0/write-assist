[PRD]
# PRD: WriteAssist Review Workbench

## Overview

WriteAssist will pivot from a system-wide inline assistant toward a focused macOS review and rewrite app for non-native English speakers.

The primary workflow is explicit review, not passive monitoring:
- the user writes or pastes text into WriteAssist
- optionally imports selected text from another app via a deliberate “Review Selection” action that first opens a lightweight review panel
- runs a full review pass over the text
- inspects issues by sentence and paragraph
- requests rewrites on demand
- compares original vs rewritten text
- accepts or rejects changes at sentence or paragraph level

The app should feel more like a private English review workbench than a Grammarly clone. Local models are the default AI path when available; cloud models remain optional fallback.

## Goals

- Help non-native English speakers improve grammar, naturalness, clarity, and paragraph flow.
- Make review explicit and high-signal instead of continuous and distracting.
- Prefer local-first AI for rewrite and explanation workflows.
- Reuse the existing deterministic review pipeline where it adds value.
- Reduce architecture complexity by removing always-on inline monitoring as the main product path.

## Quality Gates

These commands must pass for every user story:
- `swift build`
- `swift test`
- `swiftlint`

## User Stories

### US-001: Create a main review-first app shell
**Description:** As a user, I want WriteAssist to open into a proper review window so that reviewing and rewriting text becomes the primary experience.

**Acceptance Criteria:**
- [ ] Launching the app opens a main review window instead of relying on floating inline HUDs as the primary UX.
- [ ] The main window has dedicated regions for input text, review results, and rewrite output.
- [ ] The menu bar item can remain, but it only launches or focuses the main review window.
- [ ] The app still builds without removing legacy code immediately.

### US-002: Support manual text entry and paste-based review
**Description:** As a user, I want to type or paste text directly into WriteAssist so that I can review emails, messages, and documents intentionally.

**Acceptance Criteria:**
- [ ] The review window includes a text editor or text input surface for manual writing and pasting.
- [ ] Replacing the entire review text is supported without relying on Accessibility APIs.
- [ ] Review text can be cleared or replaced in one action.
- [ ] The app does not require continuous system-wide monitoring to be useful.

### US-003: Add explicit “Review Selection” import flow
**Description:** As a user, I want to deliberately send selected text from another app into WriteAssist so that I can review external text without passive monitoring.

**Acceptance Criteria:**
- [ ] The app exposes a menu bar or shortcut-driven “Review Selection” action.
- [ ] The action imports the current text selection once, into a lightweight review panel with a clear path to the main review window.
- [ ] The feature does not depend on permanent selection polling or continuous typing capture.
- [ ] If selection import is unavailable, the app fails gracefully with a user-facing message.

### US-004: Run deterministic full-review analysis on demand or explicit text changes
**Description:** As a user, I want WriteAssist to analyze my text for concrete issues so that I can review grammar, style, and clarity before rewriting.

**Acceptance Criteria:**
- [ ] A review pass analyzes the current text using the existing deterministic pipeline where applicable.
- [ ] Review results include spelling, grammar, clarity, engagement, and delivery/style issues when available.
- [ ] Analysis runs against the current review document, not a hidden rolling system-wide buffer.
- [ ] The review UI clearly indicates when analysis is in progress and when results are fresh.

### US-005: Group findings by sentence and paragraph
**Description:** As a user, I want issues organized by paragraph and sentence so that I can fix awkward structure instead of chasing isolated tokens.

**Acceptance Criteria:**
- [ ] Review results can be inspected by paragraph.
- [ ] Paragraphs show their relevant sentence- or range-level issues.
- [ ] Selecting an issue highlights the relevant text in the review surface.
- [ ] The UI supports reviewing text structure, not just flat issue lists.

### US-006: Request on-demand sentence and paragraph rewrites
**Description:** As a user, I want to explicitly ask WriteAssist to rewrite a sentence or paragraph so that I can improve naturalness, tone, and flow.

**Acceptance Criteria:**
- [ ] The user can request rewrite actions for a selected sentence or paragraph.
- [ ] Rewrite modes include at least grammar fix, more natural English, shorter, and more formal.
- [ ] Rewrites are AI-driven and are not automatically triggered on every keystroke.
- [ ] Local AI providers are preferred when configured; optional cloud fallback remains available.

### US-007: Compare original and rewritten text before applying changes
**Description:** As a user, I want side-by-side or diff-style compare UI so that I can decide which rewrite to accept.

**Acceptance Criteria:**
- [ ] The app shows original and rewritten versions together for the current rewrite target.
- [ ] The user can accept or reject a rewrite without losing the original text.
- [ ] Acceptance works at sentence or paragraph scope.
- [ ] The applied rewrite updates the review document and re-runs analysis as needed.

### US-008: Configure local-first AI behavior and fallback
**Description:** As a user, I want to choose local-first AI with optional cloud fallback so that the app stays cheap and private by default.

**Acceptance Criteria:**
- [ ] Settings expose local model/provider configuration as the preferred rewrite path.
- [ ] Cloud providers remain optional and disabled unless explicitly configured.
- [ ] The active provider choice is visible to the user before running rewrites.
- [ ] The app handles unavailable local models with clear fallback or error behavior.

### US-009: Demote legacy always-on inline monitoring from the primary product path
**Description:** As a maintainer, I want the old system-wide inline assistant path marked as legacy so that new development aligns with the review-workbench direction.

**Acceptance Criteria:**
- [ ] New product docs identify the review workbench as the primary experience.
- [ ] Continuous system-wide monitoring is no longer treated as the default interaction model.
- [ ] Legacy inline subsystems are clearly marked for retirement, simplification, or optional later use.
- [ ] Migration work can proceed incrementally without breaking the app immediately.

## Functional Requirements

- FR-1: The system must provide a main review window as the primary app surface.
- FR-2: The system must support manual writing and paste-in review.
- FR-3: The system must support explicit one-shot selection import from another app into a lightweight review panel, with an explicit handoff to the main workspace.
- FR-4: The system must run deterministic review analysis against the current review text.
- FR-5: The system must present issues grouped in a way that supports sentence- and paragraph-level review.
- FR-6: The system must support explicit sentence- and paragraph-level rewrite actions.
- FR-7: The system must prefer local AI providers for rewrite/explanation workflows when configured.
- FR-8: The system must allow optional cloud fallback for rewrite workflows.
- FR-9: The system must support compare-and-accept rewrite application back into the review document.
- FR-10: The system must not require always-on typing capture, floating HUDs, or permanent selection polling to deliver core value.

## Non-Goals (Out of Scope)

- Continuous Grammarly-style inline monitoring as the primary product mode.
- Always-on floating HUDs and rewrite panels across all apps.
- Permanent global typing capture as a core requirement.
- Real-time per-keystroke AI rewriting.
- Multi-user collaboration, sync, or cloud document storage.
- Local history, saved snippets, or long-term document libraries in V1.
- Full “replace back into source app” workflows in V1.

## Technical Considerations

- Prefer reusing these current subsystems where they still fit the product:
  - `SpellCheckService`
  - `NLAnalysisService`
  - `RuleEngine` and `WritingRules/*`
  - `DocumentMetrics`
  - `WritingIssue`
  - `CloudAIService` / `OllamaService`
  - `PreferencesManager`, `PersonalDictionary`, `IgnoreRulesStore`
- Treat these subsystems as legacy / non-primary:
  - `GlobalInputMonitor`
  - `SelectionMonitor`
  - `ExternalSpellChecker`
  - `ErrorHUDPanel`
  - `SelectionSuggestionPanel`
  - `UndoToastPanel`
  - `GlobalKeyEventRouter`
  - most AX-driven correction flows
- The new architecture should separate:
  - review document state
  - deterministic analysis state
  - rewrite session state
  - app-shell / menu-bar launching behavior
- Local-first AI means rewrite latency can be explicit and user-initiated rather than inline-real-time.

## Success Metrics

- The app is useful without enabling continuous system-wide monitoring.
- A user can paste text, review issues, request rewrites, and accept changes in one focused session.
- Deterministic review and AI rewrite flows are clearly separated in the UI.
- Local-first rewrite works when a local model is configured.
- The codebase has an explicit product direction that contributors can follow.

## Open Questions

- Should “Review Selection” use a global shortcut in V1, or only a menu bar action?
- Should sentence-level and paragraph-level rewrite both ship in the first pass, or can one land before the other?
- Should explanations (“why this sounds wrong”) ship alongside rewrites in V1, or immediately after?
- How should the app communicate when local AI is unavailable but cloud fallback is configured?
[/PRD]
