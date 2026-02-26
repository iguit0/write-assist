# Rule Engine Correctness — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix four correctness gaps in the writing rule engine: (1) false positives from substring matches in phrase-based rules, (2) wrong range reported for duplicate sentences, (3) only 8 of 31 confused-word pairs ever flag anything, and (4) `WritingIssue.isIgnored` dead code that causes confusion.

**Architecture:** Changes are confined to `Sources/WritingRules/`, `Sources/NLAnalysisService.swift`, `Sources/RuleEngine.swift`, and `Sources/WritingIssue.swift`. No protocol or API surface changes visible to callers outside the rule engine.

**Tech Stack:** Swift, NaturalLanguage framework, existing `WritingRule` protocol.

---

### Task 1: Extract shared word-boundary helper and apply to FormalityRule, RedundancyRule, WordinessRule

**Problem:** `FormalityRule.findAndReport`, `RedundancyRule.check`, and `WordinessRule.check` use bare `lower.range(of: phrase)` with no boundary check. This produces false positives: "use" fires inside "refuse", "open" fires inside "reopen", "commence" fires inside "recommence". `HedgingRule` and `InclusiveLanguageRule` already have the correct boundary check — extract it and apply it everywhere.

**Files:**
- Modify: `Sources/RuleEngine.swift` (add helper extension)
- Modify: `Sources/WritingRules/FormalityRule.swift` (`findAndReport` method)
- Modify: `Sources/WritingRules/RedundancyRule.swift` (`check` method)
- Modify: `Sources/WritingRules/WordinessRule.swift` (`check` method)

**Step 1: Add `isWordBounded` extension to `WritingRule` in RuleEngine.swift**

Add the following extension after the `RuleRegistry` enum in `Sources/RuleEngine.swift`:

```swift
// MARK: - Shared Helpers

extension WritingRule {
    /// Returns true if `range` in `text` is bounded by non-letter characters
    /// (or is at the start/end of the string). Prevents matching phrases
    /// inside larger words (e.g., "use" inside "refuse").
    func isWordBounded(_ range: Range<String.Index>, in text: String) -> Bool {
        let before: Character? = range.lowerBound > text.startIndex
            ? text[text.index(before: range.lowerBound)]
            : nil
        let after: Character? = range.upperBound < text.endIndex
            ? text[range.upperBound]
            : nil
        return (before == nil || !before!.isLetter)
            && (after  == nil || !after!.isLetter)
    }
}
```

**Step 2: Apply boundary check in `FormalityRule.findAndReport`**

In `Sources/WritingRules/FormalityRule.swift`, inside `findAndReport`, add the boundary guard after finding the range:

```swift
// Before (current):
while let range = lower.range(of: phrase, range: searchStart..<lower.endIndex) {
    let nsRange = NSRange(range, in: fullText)
    guard nsRange.location + nsRange.length <= nsText.length else { break }
    // ... append issue

// After:
while let range = lower.range(of: phrase, range: searchStart..<lower.endIndex) {
    guard isWordBounded(range, in: lower) else {
        searchStart = range.upperBound
        continue
    }
    let nsRange = NSRange(range, in: fullText)
    guard nsRange.location + nsRange.length <= nsText.length else { break }
    // ... append issue
```

**Step 3: Apply boundary check in `RedundancyRule.check`**

In `Sources/WritingRules/RedundancyRule.swift`, inside the `while let range` loop:

```swift
// Add guard after finding range:
while let range = lower.range(of: phrase, range: searchStart..<lower.endIndex) {
    guard isWordBounded(range, in: lower) else {
        searchStart = range.upperBound
        continue
    }
    let nsRange = NSRange(range, in: text)
    // ... rest unchanged
```

**Step 4: Apply boundary check in `WordinessRule.check`**

Same pattern as Task 1 Step 3, applied to `Sources/WritingRules/WordinessRule.swift`.

**Step 5: Build and lint**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`, zero errors/warnings.

**Step 6: Commit**

```bash
git add Sources/RuleEngine.swift Sources/WritingRules/FormalityRule.swift \
        Sources/WritingRules/RedundancyRule.swift Sources/WritingRules/WordinessRule.swift
git commit -m "fix(rules): extract shared word-boundary helper and apply to phrase-matching rules

FormalityRule, RedundancyRule, and WordinessRule were matching phrases
inside larger words (e.g. 'use' inside 'refuse'). Extract the boundary
check already used in HedgingRule/InclusiveLanguageRule into a shared
WritingRule extension and apply it consistently across all phrase rules."
```

---

### Task 2: Fix sentence range resolution to handle duplicate sentences

**Problem:** `CapitalizationRule`, `RunOnSentenceRule`, and `SentenceFragmentRule` each call `text.range(of: sentence)` to find the sentence's position. This always returns the *first* occurrence — if the same sentence appears twice, both issues are reported at the first occurrence's range.

**Solution:** Replace the `text.range(of:)` call in each rule with an advancing-search-start approach, so each lookup begins after the previous match. Additionally update `NLAnalysisService.tokenizeSentences` to return `[(String, Range<String.Index>)]` (the tokenizer already has the correct ranges — we're just throwing them away today).

**Files:**
- Modify: `Sources/NLAnalysisService.swift` (`tokenizeSentences`, `NLAnalysis` struct)
- Modify: `Sources/WritingRules/CapitalizationRule.swift`
- Modify: `Sources/WritingRules/RunOnSentenceRule.swift`
- Modify: `Sources/WritingRules/SentenceFragmentRule.swift`

**Step 1: Update `NLAnalysis` to store sentence ranges**

In `Sources/NLAnalysisService.swift`, change `NLAnalysis`:

```swift
// Before:
struct NLAnalysis: Sendable {
    let sentences: [String]
    // ...

// After:
struct NLAnalysis: Sendable {
    /// Each element pairs the sentence string with its exact range in the
    /// original text, as reported by NLTokenizer. Use this range in rules
    /// instead of re-searching with text.range(of:) to avoid duplicate-sentence bugs.
    let sentenceRanges: [(sentence: String, range: Range<String.Index>)]
    // Keep backward-compat accessor:
    var sentences: [String] { sentenceRanges.map(\.sentence) }
    // ...
```

**Step 2: Update `tokenizeSentences` to return ranges**

```swift
// Before:
static func tokenizeSentences(_ text: String) -> [String] {
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text
    var sentences: [String] = []
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
        let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !sentence.isEmpty {
            sentences.append(sentence)
        }
        return true
    }
    return sentences
}

// After:
static func tokenizeSentences(_ text: String) -> [(sentence: String, range: Range<String.Index>)] {
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text
    var results: [(sentence: String, range: Range<String.Index>)] = []
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
        let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !sentence.isEmpty {
            results.append((sentence: sentence, range: range))
        }
        return true
    }
    return results
}
```

Update `analyze()` to pass the result:

```swift
// Before:
let sentences = tokenizeSentences(text)
// ...
return NLAnalysis(sentences: sentences, ...)

// After:
let sentenceRanges = tokenizeSentences(text)
// ...
return NLAnalysis(sentenceRanges: sentenceRanges, ...)
```

**Step 3: Update `CapitalizationRule` to use `analysis.sentenceRanges`**

```swift
// Before:
for sentence in analysis.sentences {
    guard let sentenceRange = text.range(of: sentence) else { continue }
    let nsRange = NSRange(sentenceRange, in: text)
    // ...

// After:
for (sentence, sentenceRange) in analysis.sentenceRanges {
    let nsRange = NSRange(sentenceRange, in: text)
    // ... rest unchanged (just remove the guard let lookup)
```

**Step 4: Update `RunOnSentenceRule` the same way**

```swift
// Before:
for sentence in analysis.sentences {
    // ...
    guard let range = text.range(of: sentence) else { continue }
    let nsRange = NSRange(range, in: text)

// After:
for (sentence, sentenceRange) in analysis.sentenceRanges {
    // ...
    let nsRange = NSRange(sentenceRange, in: text)
```

**Step 5: Update `SentenceFragmentRule` the same way**

```swift
// Before:
for sentence in analysis.sentences {
    // ...
    guard let range = text.range(of: sentence) else { continue }
    let nsRange = NSRange(range, in: text)

// After:
for (sentence, sentenceRange) in analysis.sentenceRanges {
    // ...
    let nsRange = NSRange(sentenceRange, in: text)
```

**Step 6: Build and lint**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`, zero errors/warnings.

**Step 7: Commit**

```bash
git add Sources/NLAnalysisService.swift \
        Sources/WritingRules/CapitalizationRule.swift \
        Sources/WritingRules/RunOnSentenceRule.swift \
        Sources/WritingRules/SentenceFragmentRule.swift
git commit -m "fix(rules): use NLTokenizer sentence ranges directly to fix duplicate-sentence bugs

CapitalizationRule, RunOnSentenceRule, and SentenceFragmentRule were using
text.range(of: sentence) which always returned the first occurrence.
Store (sentence, range) tuples from NLTokenizer in NLAnalysis so rules
can use the exact tokenizer-reported range instead of re-searching."
```

---

### Task 3: Expand ConfusedWordRule to flag all 31 pairs

**Problem:** `shouldFlagWord` returns `false` for 23 of 31 word pairs because POS-tag heuristics are unreliable for these words. Only 8 specific cases ("affect", "effect", "advice", "advise", "breath", "breathe") are ever flagged. The remaining 23 pairs (their/there/they're, desert/dessert, moral/morale, etc.) never produce any output despite being defined.

**Solution:** Remove the `shouldFlagWord` guard and always flag confused words as informational hints. This matches how Grammarly and similar tools work — they surface the hint for all occurrences to prompt a double-check, trusting the user to dismiss false positives. Keep the message text neutral ("Check: could you mean X?") to reduce perceived false-positive friction.

**Files:**
- Modify: `Sources/WritingRules/ConfusedWordRule.swift`

**Step 1: Replace `check()` and remove `shouldFlagWord`**

Replace the entire `check(text:analysis:)` method and remove `shouldFlagWord` entirely:

```swift
func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
    var issues: [WritingIssue] = []

    for (word, _, range) in analysis.wordPOSTags {
        let lower = word.lowercased()
        guard let matchingPairs = Self.wordToPairs[lower] else { continue }

        for pair in matchingPairs {
            let nsRange = NSRange(range, in: text)
            let alternatives = pair.words.filter { $0.lowercased() != lower }
            issues.append(WritingIssue(
                type: .confusedWord,
                range: nsRange,
                word: word,
                message: pair.hint,
                suggestions: alternatives
            ))
        }
    }

    return issues
}
```

Delete the `shouldFlagWord` method entirely.

**Step 2: Build and lint**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`, zero errors/warnings.

**Step 3: Manual verification**

Run `swift run` and type sentences with common confused words in any text editor:

| Input | Expected |
|-------|----------|
| "The weather is nice." | Flag "weather" with desert/dessert hint |
| "He was the principal actor." | Flag "principal" with hint |
| "The moral of the story" | Flag "moral" with morale hint |
| "There are three options." | Flag "there" with their/they're hint |

**Step 4: Commit**

```bash
git add Sources/WritingRules/ConfusedWordRule.swift
git commit -m "fix(rules): flag all 31 confused-word pairs instead of just 8

shouldFlagWord returned false for 23 of 31 pairs because POS heuristics
are unreliable without deeper syntactic context. Remove the POS gate and
flag all pairs as informational hints — users can dismiss false positives,
but missing real confused words (their/there, moral/morale, etc.) is worse."
```

---

### Task 4: Remove `WritingIssue.isIgnored` dead code

**Problem:** `WritingIssue.isIgnored` is declared as `var isIgnored: Bool = false` but is never set to `true`. The ignore mechanism in `DocumentViewModel.ignoreIssue()` removes the issue from the `issues` array rather than toggling the flag. This means every `!$0.isIgnored` filter in computed properties and `HighlightedTextView` is a permanent no-op that adds confusion to the codebase.

**Files:**
- Modify: `Sources/WritingIssue.swift` (remove `isIgnored` property)
- Modify: `Sources/DocumentViewModel.swift` (remove `!$0.isIgnored` filters)
- Modify: `Sources/HighlightedTextView.swift` (remove `!issue.isIgnored` guard)

**Step 1: Remove `isIgnored` from `WritingIssue`**

In `Sources/WritingIssue.swift`, remove the last property:

```swift
// Before:
struct WritingIssue: Identifiable, Sendable {
    let id = UUID()
    let type: IssueType
    let range: NSRange
    let word: String
    let message: String
    let suggestions: [String]
    var isIgnored: Bool = false   // ← remove this line
}

// After:
struct WritingIssue: Identifiable, Sendable {
    let id = UUID()
    let type: IssueType
    let range: NSRange
    let word: String
    let message: String
    let suggestions: [String]
}
```

**Step 2: Remove `!$0.isIgnored` filters in `DocumentViewModel`**

In `Sources/DocumentViewModel.swift`, update the issue count computed properties to remove the dead filter:

```swift
// Before:
var spellingCount: Int { issues.filter { $0.type == .spelling && !$0.isIgnored }.count }
var grammarCount: Int  { issues.filter { $0.type == .grammar  && !$0.isIgnored }.count }
var clarityCount: Int  { issues.filter { $0.type.category == .clarity  && !$0.isIgnored }.count }
var styleCount: Int    { issues.filter { $0.type.category == .delivery && !$0.isIgnored }.count }
var engagementCount: Int { issues.filter { $0.type.category == .engagement && !$0.isIgnored }.count }
var totalActiveIssueCount: Int { issues.filter { !$0.isIgnored }.count }
var filteredIssues: [WritingIssue] {
    let active = issues.filter { !$0.isIgnored }
    // ...
}

// After:
var spellingCount: Int  { issues.filter { $0.type == .spelling }.count }
var grammarCount: Int   { issues.filter { $0.type == .grammar }.count }
var clarityCount: Int   { issues.filter { $0.type.category == .clarity }.count }
var styleCount: Int     { issues.filter { $0.type.category == .delivery }.count }
var engagementCount: Int { issues.filter { $0.type.category == .engagement }.count }
var totalActiveIssueCount: Int { issues.count }
var filteredIssues: [WritingIssue] {
    guard let category = selectedCategory else { return issues }
    return issues.filter { $0.type.category == category }
}
```

**Step 3: Remove guard in `HighlightedTextView.buildAttributedString`**

In `Sources/HighlightedTextView.swift`:

```swift
// Before:
for issue in issues where !issue.isIgnored {

// After:
for issue in issues {
```

**Step 4: Build and lint**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`, zero errors/warnings.

**Step 5: Commit**

```bash
git add Sources/WritingIssue.swift Sources/DocumentViewModel.swift \
        Sources/HighlightedTextView.swift
git commit -m "refactor: remove WritingIssue.isIgnored dead code

isIgnored was never set to true — ignoreIssue() removes issues from the
array rather than toggling the flag. All !isIgnored filters were no-ops.
Remove the property and simplify the computed properties that used it."
```
