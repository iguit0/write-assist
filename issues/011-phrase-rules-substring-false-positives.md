# `FormalityRule`, `RedundancyRule`, `WordinessRule` match phrases inside larger words

**Labels:** `bug` `P1-high`  
**Status:** 🔧 In Progress — see `docs/plans/2026-02-24-rule-engine-correctness-plan.md` (Task 1)

## Description

Three phrase-matching rules use bare `lower.range(of: phrase)` without a word-boundary check, causing false positives when the phrase is a substring of a longer word:

- `FormalityRule`: "use" matches inside "refuse", "commence" matches inside "recommence"
- `RedundancyRule`: "open" matches inside "reopen", "end result" matches inside "blend result"
- `WordinessRule`: "in order to" correctly requires full match, but shorter phrases can fire inside words

`HedgingRule` and `InclusiveLanguageRule` already have the correct `isWordBounded` check — it just hasn't been applied consistently.

## Affected Files

- `Sources/WritingRules/FormalityRule.swift` — `findAndReport` method
- `Sources/WritingRules/RedundancyRule.swift` — `check` method
- `Sources/WritingRules/WordinessRule.swift` — `check` method

## Steps to Reproduce

1. In a monitored text editor, type: *"I refuse to commence the presentation."*
2. **Expected:** no false positives (no formality flags on "refuse" or "recommence").
3. **Actual:** "use" inside "refuse" may be flagged by FormalityRule.

## Proposed Fix

Extract the `isWordBounded` helper already present in `HedgingRule`/`InclusiveLanguageRule` into a `WritingRule` protocol extension in `RuleEngine.swift`, then apply it in all three phrase-matching rules.

Full implementation in `docs/plans/2026-02-24-rule-engine-correctness-plan.md` (Task 1).
