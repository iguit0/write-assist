# User text logged at `info`/`debug` level — privacy concern

**Labels:** `security` `privacy` `P1-high`  
**Status:** 🆕 New

## Description

WriteAssist captures every keystroke typed in any application on the Mac. Multiple `logger.info` and `logger.debug` calls record actual user text content — including corrections, words, and buffer snippets — to the unified logging system:

```swift
logger.info("applyCorrection: '\(issue.word)' → '\(correction)'")
logger.debug("buffer tail: \(bufferTail)")
logger.info("readWordBeforeCursor: '\(wordBeforeCursor)'")
```

macOS unified logging persists `info`-level messages to disk and they can be read by diagnostic tools, crash reporters, and anyone with root access to the machine or a collected `.logarchive`. Because WriteAssist monitors all keystrokes, this could expose passwords typed in other apps if they appear in the 500-character rolling buffer.

## Affected Files

- `Sources/DocumentViewModel.swift` — multiple `logger.info`/`logger.debug` calls with user text
- `Sources/GlobalInputMonitor.swift` — buffer contents in debug logs
- `Sources/ExternalSpellChecker.swift` — word-before-cursor in logs
- `Sources/ErrorHUDPanel.swift` — `logger.debug("onApply: user selected '\(suggestion)'")`

## Proposed Fix

Replace all logs that include user text content with either:

1. **Redacted metadata** — log structural info only:
   ```swift
   logger.info("applyCorrection: wordLength=\(issue.word.count), suggestionCount=\(issue.suggestions.count)")
   ```

2. **`OSLogPrivacy.sensitive`** — marks the value as sensitive so it is redacted in collected logs unless the device is in developer mode:
   ```swift
   logger.info("applyCorrection: '\(issue.word, privacy: .sensitive)' → '\(correction, privacy: .sensitive)'")
   ```

Option 2 is preferred as it preserves debuggability for developers while protecting user privacy in production log collections.

## Additional Context

The app's privacy policy (if any) should also disclose that correction events are logged locally. Consider adding a "Clear log" or "Disable debug logging" option in Settings for privacy-conscious users.
