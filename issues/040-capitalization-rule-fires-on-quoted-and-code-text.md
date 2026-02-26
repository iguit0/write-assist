# `CapitalizationRule` false-positives on code snippets, quoted text, and brand names

**Labels:** `bug` `ux` `P3-low`  
**Status:** ✅ Fixed — `CapitalizationRule` now suppresses false-positives via three heuristics: (1) skip single-character tokens, (2) skip words containing code-indicator chars (`/ . _ ( ) =`) or starting with `~`, (3) skip known lowercase-start Apple brand names (`macOS`, `iOS`, etc.) (#040)

## Description

`CapitalizationRule` flags the first word of any sentence that does not begin with an uppercase letter. This correctly catches "hello World." but also incorrectly flags:

- **Code snippets embedded in prose:** `"Use let x = 5 to declare a constant."` — flags `let` as requiring capitalisation
- **Quoted speech starting with lowercase:** `'she said "hello world."'` — flags "hello"
- **Intentional stylistic lowercase brands:** "Use macOS, iOS, or watchOS for development." — all three would be flagged if they appear at sentence start
- **List items starting with lowercase:** markdown-style `"- open the file"` lists
- **File paths or URLs at sentence start:** `"~/Documents is the default folder."`

## Affected Files

- `Sources/WritingRules/CapitalizationRule.swift`

## Proposed Fix

Add suppression heuristics before flagging a sentence:

1. **Skip if first word contains special characters:** if the word contains `/`, `.`, `_`, `(`, `)`, `=`, or starts with `~`, it is likely a path, code token, or URL.

2. **Skip known lowercase brands:** maintain a small set of known legitimate lowercase-start identifiers: `{"macOS", "iOS", "iPadOS", "watchOS", "tvOS", "visionOS", "iCloud", "iPhone", "iPad", "iMac", "HomePod"}`. If the first word is in this set, do not flag it.

3. **Skip single-character words followed by period:** "e.g." and "i.e." at sentence start should not be flagged.

```swift
private static let legitimateLowercaseStarts: Set<String> = [
    "macOS", "iOS", "iPadOS", "watchOS", "tvOS", "visionOS",
    "iCloud", "iPhone", "iPad", "iMac", "HomePod"
]

func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
    for (sentence, sentenceRange) in analysis.sentenceRanges {
        let firstWord = sentence.components(separatedBy: .whitespaces).first ?? ""
        guard !firstWord.isEmpty,
              firstWord.first?.isLetter == true,        // skip code/paths
              !Self.legitimateLowercaseStarts.contains(firstWord),  // skip brands
              firstWord.first!.isLowercase else { continue }
        // ... flag issue
    }
}
```
