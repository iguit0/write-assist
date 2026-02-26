# Persistent ignore is completely non-functional

**Labels:** `bug` `P1-high`  
**Status:** 🔧 In Progress — see `docs/plans/2026-02-24-writing-issue-and-ai-service-plan.md` (Task 1)

## Description

The "ignore" action in the HUD has two independent bugs that together make persistent ignore completely broken:

1. **Wrong lookup key.** `DocumentViewModel.runCheck()` calls `ignoreStore.isIgnored(word:ruleID:)` with `$0.type.categoryLabel` (display strings like `"Double Word"`, `"Passive Voice"`). But `IgnoreRulesStore` stores rules using `WritingRule.ruleID` (camelCase identifiers like `"doubleWord"`, `"passiveVoice"`). The keys never match — every issue passes through the filter on every check.

2. **`addRule` is never called.** `ErrorHUDPanel`'s ignore action calls `viewModel.ignoreIssue()`, which only removes the issue from the in-memory `issues` array for the current session. `IgnoreRulesStore.addRule` — the persistent cross-session store — has **no call site anywhere in the codebase**.

Users who press "i" to ignore an issue see it disappear temporarily, but it reappears on the next check and reappears again after relaunch.

## Affected Files

- `Sources/DocumentViewModel.swift` — `runCheck()` filter using `$0.type.categoryLabel`
- `Sources/ErrorHUDPanel.swift` — ignore key handler (never calls `IgnoreRulesStore.addRule`)
- `Sources/WritingIssue.swift` — needs a `ruleID: String` property to carry the stable identifier

## Proposed Fix

See `docs/plans/2026-02-24-writing-issue-and-ai-service-plan.md` (Task 1) for the complete fix:

1. Add `ruleID: String` to `WritingIssue`, populated by each rule via `self.ruleID`.
2. Fix `runCheck()` to use `$0.ruleID` instead of `$0.type.categoryLabel`.
3. Wire `IgnoreRulesStore.addRule(word:ruleID:)` into the HUD ignore action alongside the existing session-only `viewModel.ignoreIssue()` call.
