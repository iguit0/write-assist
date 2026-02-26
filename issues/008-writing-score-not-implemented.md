# Writing score is a dead placeholder — no implementation

**Labels:** `bug` `enhancement` `P1-high`  
**Status:** 🆕 New

## Description

`DocumentViewModel` has a `// MARK: - Writing Score` section with a doc comment describing a multi-dimensional writing score ("combining correctness, clarity, engagement, and delivery") but **zero implementation**. `ContentView.swift` has a matching `// MARK: - Score Badge` section with no code beneath it.

This means the writing score UI element is either silently absent or would cause a compile error if any view tried to reference `viewModel.writingScore`. The feature appears in the architecture documentation but is unreachable by users.

## Affected Files

- `Sources/DocumentViewModel.swift` — `// MARK: - Writing Score` placeholder
- `Sources/ContentView.swift` — `// MARK: - Score Badge` placeholder

## Proposed Fix

Implement a `var writingScore: Int` computed property on `DocumentViewModel`:

```swift
/// Writing score from 0–100. Starts at 100 and subtracts weighted penalties
/// for each active issue category.
var writingScore: Int {
    guard !currentText.isEmpty else { return 100 }
    let spellingPenalty  = min(spellingCount  * 5, 30)
    let grammarPenalty   = min(grammarCount   * 4, 20)
    let clarityPenalty   = min(clarityCount   * 3, 20)
    let stylePenalty     = min(styleCount     * 2, 15)
    let engagementPenalty = min(engagementCount * 2, 15)
    return max(0, 100 - spellingPenalty - grammarPenalty
                      - clarityPenalty - stylePenalty - engagementPenalty)
}
```

Then surface the score in the UI as a circular badge or a labelled meter in the Issues tab header.

## Additional Context

The PRD (tasks/prd-writeassist.md) does not explicitly specify a writing score, but the placeholder strongly implies it was part of the original design intent. If the feature is intentionally deferred, remove the placeholder comments to avoid confusion.
