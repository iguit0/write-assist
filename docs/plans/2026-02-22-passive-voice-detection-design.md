# Improved Passive Voice Detection

## Problem

The current `PassiveVoiceRule` misses roughly half of all passive voice constructions due to two issues:

1. **Irregular past participles not detected.** The rule checks for suffixes `-ed`, `-en`, `-wn`, `-ne` only. Common irregular forms like "taught", "built", "kept", "held", "told", "found", "thought", "lost", "run", "cut", "put", "hit" (~100 words) are invisible.

2. **Multi-word auxiliary matching is broken.** The `toBeVerbs` set contains entries like `"has been"` and `"will be"`, but the code compares against single tokens from NLTagger. These never match, so constructions like "has been written" or "will be reviewed" are missed.

## Solution

Modify `Sources/WritingRules/PassiveVoiceRule.swift` with two changes:

### Change 1: Irregular Past Participle Set

Add a `static let irregularPastParticiples: Set<String>` containing ~150 irregular forms. Replace the suffix-only check:

```swift
// Before:
guard nextLower.hasSuffix("ed") || nextLower.hasSuffix("en")
    || nextLower.hasSuffix("wn") || nextLower.hasSuffix("ne") else { continue }

// After:
guard Self.isPastParticiple(nextLower) else { continue }

private static func isPastParticiple(_ word: String) -> Bool {
    word.hasSuffix("ed") || irregularPastParticiples.contains(word)
}
```

### Change 2: Fix Multi-Word Auxiliary Matching

Split `toBeVerbs` into two sets:

- `toBeVerbs`: single-word "to be" forms (`is`, `are`, `was`, `were`, `am`, `be`, `been`, `being`)
- `auxiliaryVerbs`: modals/helpers (`has`, `have`, `had`, `will`, `shall`, `could`, `would`, `might`, `must`, `should`)

Detection logic:

1. If current token is in `toBeVerbs` → skip optional adverb → check for past participle
2. If current token is in `auxiliaryVerbs` → skip optional adverb → expect `be`/`been`/`being` → skip optional adverb → check for past participle

The phrase range spans from the first auxiliary/to-be token to the past participle.

## What This Catches

| Before | After |
|--------|-------|
| "was reviewed" | "was reviewed" |
| "is broken" | "is broken" |
| (missed) "was taught" | "was taught" |
| (missed) "was built" | "was built" |
| (missed) "has been written" | "has been written" |
| (missed) "could be told" | "could be told" |
| (missed) "will be kept" | "will be kept" |
| (missed) "must be found" | "must be found" |

## Scope

- One file modified: `Sources/WritingRules/PassiveVoiceRule.swift`
- No new files, no new dependencies, no JSON resources
- Irregular list is inline as a `Set<String>` literal

## Verification

1. `swift build` — zero errors/warnings
2. `swiftlint` — zero violations
3. Manual test: type sentences in a text editor with WriteAssist running:
   - "The report was taught by the professor." (should flag "was taught")
   - "The bridge has been built." (should flag "has been built")
   - "It could be kept secret." (should flag "could be kept")
   - "She was running." (should NOT flag — progressive, not passive)
   - "He writes code." (should NOT flag — active voice)
