# Writing Issue Model & AI Service Fixes — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix three correctness bugs identified in code review: (1) the persistent ignore feature is non-functional because `runCheck()` uses display labels instead of stable rule IDs for the lookup key, and `IgnoreRulesStore.addRule` is never called; (2) two concurrent AI calls can both bypass the rate limiter; (3) `HighlightedTextView.Coordinator` retains a stale selection callback after parent re-renders.

**Architecture:** Changes touch `Sources/WritingIssue.swift`, `Sources/DocumentViewModel.swift`, `Sources/ErrorHUDPanel.swift`, `Sources/CloudAIService.swift`, and `Sources/HighlightedTextView.swift`. No public API surface changes visible outside these files.

**Tech Stack:** Swift 6 strict concurrency (`@MainActor`), `ContinuousClock`, AppKit `NSViewRepresentable`.

---

### Task 1: Fix persistent ignore — wire up `addRule` and use `ruleID` in the lookup

**Problem:** Two independent bugs make the persistent ignore feature completely non-functional:

1. **Wrong lookup key.** In `DocumentViewModel.runCheck()` (line ~280):
   ```swift
   && !ignoreStore.isIgnored(word: $0.word, ruleID: $0.type.categoryLabel)
   ```
   `categoryLabel` returns display strings like `"Double Word"`, `"Passive Voice"`. But `WritingRule.ruleID` uses stable camelCase identifiers like `"doubleWord"`, `"passiveVoice"`. The keys never match.

2. **`addRule` is never called.** The HUD's 'i' (ignore) action calls `viewModel.ignoreIssue()` which only does a session-scoped in-memory remove. `IgnoreRulesStore.addRule` — the persistent, cross-session store — has no call site.

**Solution:**
- Add a `ruleID: String` property to `WritingIssue` populated by each rule.
- Fix `runCheck()` to use `$0.ruleID` instead of `$0.type.categoryLabel`.
- Wire up `IgnoreRulesStore.addRule` from the HUD 'i' ignore action.
- Assign `ruleID = "spelling"` for issues created by `SpellCheckService` and `CloudAIService`.

**Files:**
- Modify: `Sources/WritingIssue.swift` (add `ruleID`)
- Modify: `Sources/RuleEngine.swift` (`WritingRule` protocol — add `ruleID` requirement or use default)
- Modify: All 11 `Sources/WritingRules/*.swift` files (pass `ruleID` when creating `WritingIssue`)
- Modify: `Sources/DocumentViewModel.swift` (`runCheck()` filter and `resolveSpellIssues`)
- Modify: `Sources/ErrorHUDPanel.swift` (wire up persistent addRule on 'i' key)

**Step 1: Add `ruleID` to `WritingIssue`**

In `Sources/WritingIssue.swift`, add `ruleID` after `type`:

```swift
struct WritingIssue: Identifiable, Sendable {
    let id = UUID()
    let type: IssueType
    let ruleID: String      // Stable identifier matching WritingRule.ruleID, or "spelling"
    let range: NSRange
    let word: String
    let message: String
    let suggestions: [String]
}
```

**Step 2: Update every `WritingIssue` initialiser call in rules**

Each rule's `check()` creates `WritingIssue(type:range:word:message:suggestions:)` — add `ruleID: ruleID` (the rule's own `self.ruleID` property). Example for `CapitalizationRule`:

```swift
issues.append(WritingIssue(
    type: .capitalization,
    ruleID: ruleID,          // add this
    range: NSRange(...),
    word: ...,
    message: ...,
    suggestions: [...]
))
```

Repeat for all 11 rules in `Sources/WritingRules/`. Also update `PassiveVoiceRule` (in `DocumentViewModel`'s `resolveSpellIssues` logic if passive is applied there — check the call site).

**Step 3: Assign `ruleID = "spelling"` for spell-check issues**

In `Sources/SpellCheckService.swift`, update the `WritingIssue` initialiser to pass `ruleID: "spelling"`.

In `Sources/CloudAIService.swift` → `parseSpellCheckResponse`, update the `WritingIssue` initialiser:

```swift
issues.append(WritingIssue(
    type: .spelling,
    ruleID: "spelling",      // add this
    range: resolvedRange,
    word: word,
    message: "Misspelled word",
    suggestions: corrections
))
```

**Step 4: Fix `runCheck()` to use `ruleID`**

In `Sources/DocumentViewModel.swift`, change the filter in `runCheck()`:

```swift
// Before:
&& !ignoreStore.isIgnored(word: $0.word, ruleID: $0.type.categoryLabel)

// After:
&& !ignoreStore.isIgnored(word: $0.word, ruleID: $0.ruleID)
```

**Step 5: Wire up persistent ignore in the HUD**

In `Sources/ErrorHUDPanel.swift`, find the 'i' key handler (inside the `HUDKeyboardState` or key monitor block). Currently it calls `viewModel?.ignoreIssue(issue)` (session-only). Add the persistent store call:

```swift
// In the ignore action (key 'i' or Ignore button tap):
// Before:
viewModel?.ignoreIssue(issue)

// After:
IgnoreRulesStore.shared.addRule(word: issue.word, ruleID: issue.ruleID)
viewModel?.ignoreIssue(issue)   // also removes from current session
```

For the "ignore all" case (if present), pass `ruleID: issue.ruleID` and `word: issue.word` to cover just this word+rule combination, or pass `ruleID: nil` to ignore this word across all rules.

**Step 6: Build and lint**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`, zero errors/warnings.

**Step 7: Manual verification**

1. Run `swift run`.
2. Type a sentence with a hedging phrase, e.g. "I think this is correct."
3. HUD appears → press 'i' to ignore.
4. Quit and relaunch the app.
5. Type the same sentence again.
6. Expected: HUD does NOT appear for "I think" (persistent ignore stored).

**Step 8: Commit**

```bash
git add Sources/WritingIssue.swift Sources/DocumentViewModel.swift \
        Sources/ErrorHUDPanel.swift Sources/SpellCheckService.swift \
        Sources/CloudAIService.swift Sources/WritingRules/
git commit -m "fix: make persistent ignore functional

Two bugs made IgnoreRulesStore non-functional:
1. runCheck() used categoryLabel (display strings) instead of ruleID
   (stable identifiers) for the isIgnored lookup — keys never matched.
2. IgnoreRulesStore.addRule was never called — ignoreIssue() only did
   a session-scoped in-memory remove.

Add ruleID to WritingIssue, propagate it from each rule, fix the
runCheck() filter, and wire addRule into the HUD ignore action so
ignored words persist across app restarts."
```

---

### Task 2: Fix rate-limiting race condition in `CloudAIService.complete()`

**Problem:** In `Sources/CloudAIService.swift`, `complete()` updates `lastRequestTime` *after* the optional sleep, not before. When two callers both find `lastRequestTime` stale and both decide to sleep for the same duration, both wake up simultaneously and both make an API call — bypassing the 1-second minimum interval.

The race:
```
lastRequestTime = T (old)
Call A: elapsed < minRequestInterval → sleeps (minRequestInterval - elapsed)
              ↑ suspension point — Call B can run now
Call B: same stale T → same elapsed → also sleeps same duration
Both wake up at T + minRequestInterval → both call API → double-fire
```

**Solution:** Reserve the slot by updating `lastRequestTime` *before* sleeping — stamping it to the intended wake-up time rather than the actual current time.

**Files:**
- Modify: `Sources/CloudAIService.swift` (`complete()` method, lines ~120–135)

**Step 1: Replace the rate-limit block in `complete()`**

```swift
// Before (current):
func complete(prompt: String, systemPrompt: String) async throws -> String {
    if let lastTime = lastRequestTime {
        let elapsed = ContinuousClock.now - lastTime
        if elapsed < minRequestInterval {
            try await Task.sleep(for: minRequestInterval - elapsed)
        }
    }
    isProcessing = true
    defer { isProcessing = false }
    lastRequestTime = .now
    // ... provider switch

// After:
func complete(prompt: String, systemPrompt: String) async throws -> String {
    // Reserve the rate-limit slot BEFORE any suspension point.
    // Updating lastRequestTime here (not after the sleep) prevents two concurrent
    // callers from both passing the elapsed check and both firing simultaneously.
    let now = ContinuousClock.now
    if let lastTime = lastRequestTime {
        let elapsed = now - lastTime
        if elapsed < minRequestInterval {
            let remaining = minRequestInterval - elapsed
            // Stamp the slot immediately so concurrent callers see a future timestamp
            lastRequestTime = lastTime + minRequestInterval
            try await Task.sleep(for: remaining)
        } else {
            lastRequestTime = now
        }
    } else {
        lastRequestTime = now
    }
    isProcessing = true
    defer { isProcessing = false }
    // ... provider switch (remove the old lastRequestTime = .now line)
```

**Step 2: Remove the old `lastRequestTime = .now` line**

The old assignment that appeared between `isProcessing = true` and the `switch provider` block must be removed — the new block above handles it.

**Step 3: Build and lint**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`, zero errors/warnings.

**Step 4: Commit**

```bash
git add Sources/CloudAIService.swift
git commit -m "fix(ai): prevent concurrent callers from bypassing rate limiter

lastRequestTime was updated after Task.sleep, not before. Two callers
could both see a stale lastRequestTime, both decide to sleep the same
duration, and both fire an API call simultaneously.

Reserve the slot by stamping lastRequestTime to the intended wake-up
time before suspending, so any concurrent caller sees a future timestamp
and waits an additional full interval."
```

---

### Task 3: Fix `HighlightedTextView.Coordinator` stale callback

**Problem:** In `Sources/HighlightedTextView.swift`, `makeCoordinator()` captures `onSelectionChanged` by value at construction time. SwiftUI calls `makeCoordinator()` once per view lifetime. If the parent re-renders with a different closure, the coordinator retains the stale old one — new selection events are silently dispatched to the wrong handler.

```swift
// Current — closure captured once, never updated:
func makeCoordinator() -> Coordinator {
    Coordinator(onSelectionChanged: onSelectionChanged)
}

class Coordinator: NSObject, NSTextViewDelegate {
    let onSelectionChanged: ((String, NSRange) -> Void)?   // `let` — immutable
    // ...
}
```

**Files:**
- Modify: `Sources/HighlightedTextView.swift`

**Step 1: Change `Coordinator.onSelectionChanged` from `let` to `var`**

```swift
class Coordinator: NSObject, NSTextViewDelegate {
    var onSelectionChanged: ((String, NSRange) -> Void)?   // `let` → `var`

    init(onSelectionChanged: ((String, NSRange) -> Void)? = nil) {
        self.onSelectionChanged = onSelectionChanged
    }
    // textViewDidChangeSelection unchanged
}
```

**Step 2: Refresh the callback in `updateNSView`**

In `updateNSView(_:context:)`, add the refresh before the attributed string update:

```swift
func updateNSView(_ scrollView: NSScrollView, context: Context) {
    // Keep the coordinator's callback in sync with the current closure.
    // makeCoordinator() is called only once, so without this update the
    // coordinator would retain a stale closure after parent re-renders.
    context.coordinator.onSelectionChanged = onSelectionChanged

    guard let textView = scrollView.documentView as? NSTextView else { return }
    textView.textStorage?.setAttributedString(buildAttributedString())
}
```

**Step 3: Build and lint**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`, zero errors/warnings.

**Step 4: Commit**

```bash
git add Sources/HighlightedTextView.swift
git commit -m "fix: refresh HighlightedTextView coordinator callback on each render

makeCoordinator() is called once per view lifetime. If the parent
re-rendered with a different onSelectionChanged closure, the coordinator
would fire the stale old handler. Refresh the callback in updateNSView
so it always reflects the current closure."
```
