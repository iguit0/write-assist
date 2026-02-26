# Two concurrent AI calls can both bypass the rate limiter

**Labels:** `bug` `P1-high`  
**Status:** 🔧 In Progress — see `docs/plans/2026-02-24-writing-issue-and-ai-service-plan.md` (Task 2)

## Description

`CloudAIService.complete()` reads `lastRequestTime`, optionally sleeps, then writes `lastRequestTime = .now` — but the write happens **after** the `Task.sleep` suspension point. When two concurrent callers both read a stale `lastRequestTime` before either has written the updated value, both determine they need to sleep the same duration, both wake up at the same time, and both fire an API call simultaneously. This violates the 1-second minimum request interval, can cause rate-limit errors from the API, and doubles API costs unexpectedly.

## Affected Files

- `Sources/CloudAIService.swift` — `complete(prompt:systemPrompt:)`, approximately lines 120–135

## Steps to Reproduce

This is a concurrency race and requires two simultaneous triggers (e.g., ExternalSpellChecker and DocumentViewModel both completing a debounce at nearly the same millisecond). It is difficult to reproduce deterministically without a test harness.

## Proposed Fix

Reserve the rate-limit slot by stamping `lastRequestTime` to the **intended wake-up time before suspending**:

```swift
let now = ContinuousClock.now
if let lastTime = lastRequestTime {
    let elapsed = now - lastTime
    if elapsed < minRequestInterval {
        // Stamp the future wake-up time BEFORE suspending so concurrent
        // callers see a future timestamp and wait an additional interval.
        lastRequestTime = lastTime + minRequestInterval
        try await Task.sleep(for: minRequestInterval - elapsed)
    } else {
        lastRequestTime = now
    }
} else {
    lastRequestTime = now
}
```

Full implementation in `docs/plans/2026-02-24-writing-issue-and-ai-service-plan.md` (Task 2).
