# `WritingIssue.isIgnored` is dead code — never set to `true`

**Labels:** `refactor` `P1-high`  
**Status:** 🔧 In Progress — see `docs/plans/2026-02-24-rule-engine-correctness-plan.md` (Task 4)

## Description

`WritingIssue` declares `var isIgnored: Bool = false`, but this property is **never set to `true`** anywhere in the codebase. The ignore mechanism in `DocumentViewModel.ignoreIssue()` removes the issue from the `issues` array entirely rather than toggling the flag.

As a result, every `filter { !$0.isIgnored }` call in `DocumentViewModel` computed properties and every `where !issue.isIgnored` guard in `HighlightedTextView` is a permanent no-op. This dead code adds confusion and makes the ignore behaviour harder to reason about.

## Affected Files

- `Sources/WritingIssue.swift` — `var isIgnored: Bool = false`
- `Sources/DocumentViewModel.swift` — multiple `!$0.isIgnored` filters in computed properties
- `Sources/HighlightedTextView.swift` — `for issue in issues where !issue.isIgnored`

## Proposed Fix

Remove the `isIgnored` property from `WritingIssue` and simplify all computed properties that filter on it. Since the ignore mechanism removes issues from the array, `totalActiveIssueCount` can simply return `issues.count`.

Full implementation with exact code changes in `docs/plans/2026-02-24-rule-engine-correctness-plan.md` (Task 4).
