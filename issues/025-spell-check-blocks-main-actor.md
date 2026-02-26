# `SpellCheckService.performCheck` runs synchronously on `@MainActor`

**Labels:** `performance` `P2-medium`  
**Status:** 🆕 New

## Description

`SpellCheckService.performCheck` calls `NSSpellChecker.checkString(_:range:types:options:inSpellDocumentWithTag:orthography:wordCount:)` synchronously while isolated to `@MainActor`. This XPC round-trip to the spell-checking daemon takes 10–50 ms typically and up to 800 ms in the worst case (bounded by the existing timeout guard). During the check, the main run loop is blocked — SwiftUI cannot re-render and key events queue up.

With a 0.2 s debounce, this runs multiple times per minute during active writing.

## Affected Files

- `Sources/SpellCheckService.swift` — `performCheck(_:range:)`, approximately lines 68–83

## Proposed Fix

Move `performCheck` off the main actor:

```swift
// Mark the method nonisolated — NSSpellChecker is thread-safe for this API
nonisolated func performCheck(_ text: String, range: NSRange) async throws -> [WritingIssue] {
    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            // existing NSSpellChecker.checkString call
            continuation.resume(returning: issues)
        }
    }
}
```

The existing 800 ms timeout guard can be implemented as a `Task.sleep` race on the caller side (in `DocumentViewModel.runCheck`).

## Additional Context

`NSSpellChecker` is documented as safe to call from background threads for spell-check operations. Only UI-related methods (like showing the spelling panel) require the main thread.
