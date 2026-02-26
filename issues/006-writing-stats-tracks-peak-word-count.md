# `WritingStatsStore` records peak word count, not actual word count

**Labels:** `bug` `P1-high`  
**Status:** 🆕 New

## Description

`WritingStatsStore.recordWordCount` uses `max` to update the session word count:

```swift
currentSessionWordCount = max(currentSessionWordCount, count)
```

This means the counter only ever increases within a session. A user who types 500 words and then deletes them all will be credited with 500 words for the session, even though they ended up with 0 words. The Statistics panel shows inflated and incorrect numbers.

## Affected Files

- `Sources/WritingStatsStore.swift` — `recordWordCount(_:)`, line ~44

## Steps to Reproduce

1. Open the WriteAssist popover → Stats tab.
2. Type 200 words in a monitored text editor.
3. Select all and delete.
4. End the session (quit and relaunch).
5. **Expected:** session recorded ~0 words (or the last observed count).
6. **Actual:** session records 200 words.

## Proposed Fix

Use direct assignment instead of `max`:

```swift
func recordWordCount(_ count: Int) {
    currentSessionWordCount = count
}
```

The session's "words written" should reflect the last observed word count when `endSession()` is called, not the peak during the session.

## Additional Context

If tracking "total words typed" (rather than "words in document at end of session") is the intended semantic, that should be a separate counter that increments only when `count > previousCount` (i.e., accumulates only additions). The current implementation does neither correctly.
