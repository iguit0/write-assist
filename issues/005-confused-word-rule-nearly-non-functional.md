# `ConfusedWordRule` silently skips 23 of 31 word pairs

**Labels:** `bug` `P1-high`  
**Status:** 🔧 In Progress — see `docs/plans/2026-02-24-rule-engine-correctness-plan.md` (Task 3)

## Description

`ConfusedWordRule.shouldFlagWord` uses POS-tag heuristics that return `false` for 23 of the 31 defined word pairs (the `default: return false` branch). Pairs like `their/there/they're`, `desert/dessert`, `moral/morale`, `stationary/stationery` and 19 others are loaded into the rule's database but **never produce any output**. Only 8 cases are ever flagged.

Users see a "Confused Words" rule that appears active in settings, but silently does nothing for most word pairs. This is a trust-eroding silent failure.

## Affected Files

- `Sources/WritingRules/ConfusedWordRule.swift` — `shouldFlagWord` method, lines ~115–151

## Steps to Reproduce

1. In any monitored text editor, type: `"The weather there is nice."`
2. `there/their/they're` is one of the 31 defined pairs.
3. **Expected:** a "Confused Words" hint appears for "there".
4. **Actual:** no hint appears.

## Proposed Fix

Remove the `shouldFlagWord` gate entirely and flag all pairs as informational hints. This matches how tools like Grammarly handle confused words — show the hint for all occurrences and let the user dismiss false positives. The message text should be neutral: *"Check: could this be 'their' or 'they're'?"*

Complete code for this fix is in `docs/plans/2026-02-24-rule-engine-correctness-plan.md` (Task 3).
