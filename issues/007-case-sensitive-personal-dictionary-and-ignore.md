# `PersonalDictionary` and `IgnoreRulesStore` are case-sensitive

**Labels:** `bug` `P1-high`  
**Status:** 🆕 New

## Description

Both stores perform case-sensitive lookups:

- `PersonalDictionary.containsWord` uses `words.contains(word)` — adding "iPhone" does not suppress "iphone".
- `IgnoreRulesStore.isIgnored` uses `Equatable` struct comparison — ignoring "affect" does not suppress "Affect" at the start of a sentence.

This means words at the start of sentences (where they are capitalised by convention) are flagged even after the user explicitly ignored them, creating a frustrating UX where the ignore action appears not to work.

## Affected Files

- `Sources/PersonalDictionary.swift` — `containsWord(_:)`, line ~47
- `Sources/IgnoreRulesStore.swift` — `isIgnored(word:ruleID:)`, line ~47

## Steps to Reproduce

1. WriteAssist flags "iPhone" as a spelling error (it is not in the system dictionary).
2. Open WriteAssist → press **Add to Dictionary** in the HUD.
3. Type "iphone" in lowercase.
4. **Expected:** no spelling error.
5. **Actual:** "iphone" is flagged because the dictionary stored "iPhone" (case-sensitive).

## Proposed Fix

Normalise to lowercase on both insert and lookup in both stores:

```swift
// PersonalDictionary
func containsWord(_ word: String) -> Bool {
    words.contains(word.lowercased())
}

func addWord(_ word: String) {
    let lower = word.lowercased()
    guard !words.contains(lower) else { return }
    words.append(lower)
    // ...
}
```

Apply the same `.lowercased()` normalisation to `IgnoreRule.word` on creation and in `isIgnored`.
