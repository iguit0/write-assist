# `SelectionMonitor` polls AX every 250 ms — continuous battery drain

**Labels:** `performance` `enhancement` `P3-low`  
**Status:** ✅ Fixed (Option A) — `SelectionMonitor` now registers `NSWorkspace` observers for `screensaverDidStart`, `willSleep`, `screensaverDidStop`, and `didWake` to set `isScreenActive`; the 250 ms polling loop skips `poll()` while `isScreenActive == false` (#038)

## Description

`SelectionMonitor` runs a 250 ms polling loop to check for text selections in the frontmost application:

```swift
// SelectionMonitor.swift
while !Task.isCancelled {
    readSelection()
    try await Task.sleep(for: .milliseconds(250))
}
```

This loop runs continuously as long as the app is active, including when:
- The screen is locked or the screensaver is running
- The Mac is on battery power with "Low Power Mode" enabled
- No text application is in the foreground
- The user is watching a video with no text editing happening

At 250 ms intervals, this is 4 AX API calls per second, 240 per minute, 14,400 per hour — creating a measurable background battery drain on MacBooks.

## Affected Files

- `Sources/SelectionMonitor.swift`

## Proposed Fix

**Option A (low effort):** Pause the loop when the screen is locked or the display is sleeping using `NSWorkspace` notifications:

```swift
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.screensaverDidStartNotification,
    object: nil, queue: .main) { _ in pauseMonitor() }
```

**Option B (better):** Increase the polling interval when on battery power using `ProcessInfo.processInfo.isLowPowerModeEnabled` and respond to `NSProcessInfo.powerStateDidChangeNotification`.

**Option C (best long-term):** Replace polling with a macOS Accessibility event observer using `AXObserver` to receive selection-change notifications only when they actually occur. This would eliminate idle CPU/battery use entirely. Note: `AXObserver` requires per-process setup and re-registration when the frontmost app changes.
