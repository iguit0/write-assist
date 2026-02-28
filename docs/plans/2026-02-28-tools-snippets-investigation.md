# Investigation: Tools Snippets Purpose

> Historical note: the snippets feature described below was removed from the application on February 28, 2026 after this investigation concluded it was not aligned with the product goal.

## Summary
The snippets feature exists mainly as lightweight supporting infrastructure for system-wide text replacement, not as a core product pillar. It feels useless now because it is buried in the UI, minimally developed, undocumented in the product narrative, and overshadowed by richer correction and AI rewrite workflows that received far more intentional integration.

## Symptoms
- The Tools > Snippets feature feels low-value in the current app.
- Snippets are not part of the documented product story or original PRD.
- The current snippets UX is a basic CRUD list hidden under a secondary Tools tab.

## Investigation Log

### 2026-02-28 / Phase 1 - Initial assessment
**Hypothesis:** The snippets feature may be unfinished, disconnected from primary workflows, or superseded by other mechanisms.
**Findings:** The issue likely is not outright absence of functionality, but weak product positioning and follow-through.
**Evidence:** User report; project file map; mandatory context-builder pass.
**Conclusion:** Needs systematic validation.

### 2026-02-28 / Phase 2 - Context builder architecture pass
**Hypothesis:** Snippets may have been added opportunistically during a broader expansion of writing-assistant features.
**Findings:** Context builder identified snippets as one branch of a larger system-wide intervention pipeline: `GlobalInputMonitor` detects triggers, `StatusBarController` wires callbacks, and `DocumentViewModel.applySnippet()` uses the same AX/clipboard replacement pipeline as corrections. It also surfaced that snippets are absent from the PRD and README, while AI rewrite and issue workflows are prominent.
**Evidence:** `Sources/App/WriteAssistApp.swift`; `Sources/StatusBarController.swift`; `Sources/GlobalInputMonitor.swift`; `Sources/DocumentViewModel.swift`; `Sources/SnippetsManager.swift`; `Sources/ContentView.swift`; `tasks/prd-writeassist.md`; `README.md`; `CLAUDE.md`.
**Conclusion:** Strong lead: snippets were added as supporting infrastructure, not as a first-class product outcome.

### 2026-02-28 / Phase 3 - Snippet implementation review
**Hypothesis:** Snippets feel useless because the implementation is intentionally tiny and lacks product depth.
**Findings:** `SnippetsManager` stores only `{id, trigger, name, expansion}` in `UserDefaults`, seeds three canned defaults (`/sig`, `/ty`, `/greet`), and offers only basic add/remove/update/match behavior. There is no categorization, import/export, onboarding, preview, usage stats, discoverability, or workflow-specific integration. `triggerPrefix` exists in storage but is not exposed in UI.
**Evidence:** `Sources/SnippetsManager.swift:9-75`.
**Conclusion:** Confirmed. The feature is technically present but product-thin.

### 2026-02-28 / Phase 4 - UX integration review
**Hypothesis:** Snippets are hidden and weakly integrated relative to higher-value workflows.
**Findings:** The menu bar popover defaults to `Issues`, not `Tools` (`Sources/ContentView.swift:9-21`). Inside `ToolsPanel`, the default sub-tab is `Dictionary`, not `Snippets` (`Sources/ContentView.swift:1205-1213`). `SnippetsView` is a minimal management form/list (`Sources/ContentView.swift:1339-1428`). By contrast, the AI selection panel auto-appears for meaningful selected text and immediately loads rewrite suggestions (`Sources/SelectionMonitor.swift:120-154`, `Sources/SelectionSuggestionPanel.swift:114-168`, `231-257`).
**Evidence:** `Sources/ContentView.swift:9-21`, `1205-1249`, `1339-1428`; `Sources/SelectionMonitor.swift:120-154`; `Sources/SelectionSuggestionPanel.swift:114-168`, `231-257`.
**Conclusion:** Confirmed. Snippets are buried; AI rewrite is surfaced proactively.

### 2026-02-28 / Phase 5 - Product-intent and history review
**Hypothesis:** Snippets were never a central product goal.
**Findings:** The original PRD contains no snippets feature, and even lists broader style/AI capabilities as out of scope for MVP (`tasks/prd-writeassist.md:1-172`). The README markets system-wide monitoring, issue HUD, writing score, and offline checking, but never mentions snippets (`README.md:1-145`). `CLAUDE.md` likewise omits snippets from architecture and key patterns (`CLAUDE.md:1-40`). Git history shows `SnippetsManager` arrived in commit `107c45e` (2026-02-24) under “Supporting infrastructure,” alongside much larger rule-engine and AI additions. Then commit `fe6a11d` (2026-02-25) fixed snippet expansion after it had been completely non-functional because `onSnippetTriggered` was never wired in `StatusBarController.setup`.
**Evidence:** `tasks/prd-writeassist.md:1-172`; `README.md:1-145`; `CLAUDE.md:1-40`; git commit `107c45e` message; git commit `fe6a11d` message; `Sources/StatusBarController.swift:97-100`; `Sources/GlobalInputMonitor.swift:232-253`.
**Conclusion:** Confirmed. Snippets were added late as infrastructure and initially shipped broken, which is strong evidence they were not a deeply designed product feature.

## Root Cause
The most evidence-backed root cause is **product/architecture drift, not a single code bug**.

Snippets were added on February 24, 2026 as part of a large “supporting infrastructure” sweep rather than a dedicated user-facing initiative. The code treats them as a simple trigger-to-expansion utility riding on existing global input and AX replacement plumbing (`SnippetsManager`, `GlobalInputMonitor`, `DocumentViewModel.applySnippet`). But the rest of the product identity evolved around issue detection, inline corrections, and later AI-assisted rewriting.

That left snippets in an awkward middle state:
- technically implemented,
- globally functional,
- but under-designed and under-promoted.

The feature is hidden behind **Tools → Snippets**, not mentioned in the product story, seeded with generic examples, and lacks the richer affordances that would make snippets strategically useful. Meanwhile, the app heavily invests in more visible and adaptive workflows — issue HUD suggestions and AI rewrite panels — which better satisfy the same user need of “help me write faster/better.”

A reinforcing signal is that snippet expansion was completely broken until February 25, 2026 because the trigger callback was never wired. A feature that ships broken, undocumented, and minimally surfaced is usually not a core reason the product exists; it is a convenience feature that survived while other bets became primary.

## Eliminated Hypotheses
- **“Snippets do nothing at all.”** Eliminated. They are wired end-to-end now: `GlobalInputMonitor` detects suffix matches, `StatusBarController` routes the callback, and `DocumentViewModel.applySnippet()` performs replacement.
- **“Snippets were part of the original MVP vision.”** Eliminated. They are absent from the PRD.
- **“The main problem is only the old wiring bug.”** Eliminated. That bug explains prior non-functionality, but not why the feature still feels strategically weak after the fix.

## Still-Open / Secondary Hypotheses
- The feature may have been intended as groundwork for a broader text-expansion/tooling suite that never shipped.
- The current snippets UI may primarily exist to justify or exercise the system-wide replacement pipeline reused by corrections.
- User value could be improved if snippets target domain-specific workflows, but that is a product decision beyond this investigation.

## Recommendations
1. Decide explicitly whether snippets are a **core workflow** or merely a **utility**.
2. If utility: demote expectations in UI/copy and keep it intentionally lightweight.
3. If core: give it product-level investment — discoverability, editing depth, onboarding, better defaults, and tighter integration with live writing flows.
4. Remove dead signals such as unexposed configurability (`triggerPrefix`) unless a follow-up feature will use them soon.
5. Add a small product/design note whenever infrastructure features are introduced so future contributors can distinguish “scaffolding” from “strategic feature.”

## Preventive Measures
- Require new user-facing features to appear in at least one durable product artifact: PRD, README, issue, or design note.
- Avoid shipping hidden secondary-tab features without a clear success metric or narrative.
- For broad infrastructure commits, document which pieces are foundational versus actually user-ready.
- Add regression tests for end-to-end feature wiring when introducing callback-based flows like snippet expansion.
