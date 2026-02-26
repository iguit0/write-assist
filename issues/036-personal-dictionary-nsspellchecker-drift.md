# `PersonalDictionary` and `NSSpellChecker` state can drift out of sync on reinstall

**Labels:** `bug` `P3-low`  
**Status:** 🆕 New

## Description

`PersonalDictionary` stores learned words in two places:
1. `UserDefaults` — the app's own `words: [String]` array (deleted on uninstall)
2. `NSSpellChecker.learnWord` — the system-wide spell-checker dictionary (persists across reinstalls)

When the app is deleted and reinstalled, `UserDefaults` is wiped but `NSSpellChecker` retains all previously learned words. The two stores are now out of sync: `PersonalDictionary.words` is empty, but `NSSpellChecker` will not flag any of the previously-learned words. If the user re-adds a word, `learnWord` is called again (a no-op), but if they try to remove a word they never re-added (because NSSpellChecker didn't flag it), `unlearnWord` won't fire and the word stays in the system dictionary permanently.

## Affected Files

- `Sources/PersonalDictionary.swift`

## Proposed Fix

On `PersonalDictionary.init`, read `NSSpellChecker`'s user dictionary list and reconcile with `UserDefaults`:

```swift
init() {
    let stored = UserDefaults.standard.stringArray(forKey: "personalDictionary") ?? []
    let systemLearned = NSSpellChecker.shared.userReplacementsDictionary  // or custom approach
    // Words in system but not in stored → add to stored (re-sync)
    // Words in stored but not in system → call learnWord to re-add
    self.words = stored
    for word in stored {
        NSSpellChecker.shared.learnWord(word)  // idempotent
    }
}
```

Note: `NSSpellChecker` doesn't expose a public API to read the full learned-words list, making full reconciliation impossible without storing our own canonical list. The most pragmatic fix is to ensure that on every launch, WriteAssist re-calls `learnWord` for all words in `UserDefaults`, making `UserDefaults` the source of truth and NSSpellChecker the cache.
