# Up to 4 simultaneous global `NSEvent` key monitors registered concurrently

**Labels:** `bug` `architecture` `P2-medium`  
**Status:** 🆕 New

## Description

The app registers up to four simultaneous `NSEvent.addGlobalMonitorForEvents(.keyDown)` monitors:

1. `GlobalInputMonitor` — always active, captures keystrokes for the rolling buffer
2. `ErrorHUDPanel` — installed when the HUD is shown (keyboard navigation)
3. `SelectionSuggestionPanel` — installed when the selection panel is shown
4. `StatusBarController` — installs a monitor for popover-dismiss key handling

During normal operation these don't overlap, but there are timing windows (e.g., HUD is shown while a selection panel is transitioning) where all four are simultaneously active. All four handlers receive the same `NSEvent` — there is no priority system or event consumption. This can result in:

- A keystroke that dismisses the HUD also being processed by the buffer monitor as user input
- The selection panel and HUD both attempting to apply corrections for the same key press
- Subtle ordering-dependent behaviour that is very hard to debug

## Affected Files

- `Sources/GlobalInputMonitor.swift`
- `Sources/ErrorHUDPanel.swift`
- `Sources/SelectionSuggestionPanel.swift`
- `Sources/StatusBarController.swift`

## Proposed Fix

Centralise all global key event handling in a single `GlobalKeyEventRouter`:

```swift
@MainActor
final class GlobalKeyEventRouter {
    private var monitor: Any?
    private var handlers: [(priority: Int, handler: (NSEvent) -> Bool)] = []
    
    func register(priority: Int, handler: @escaping (NSEvent) -> Bool) { ... }
    func unregister(...) { ... }
    
    private func startMonitor() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Deliver to handlers in priority order; stop if any returns true (consumed)
            for (_, handler) in self?.handlers.sorted(by: { $0.priority > $1.priority }) ?? [] {
                if handler(event) { return }
            }
        }
    }
}
```

`GlobalInputMonitor` always registers at low priority. `ErrorHUDPanel` and `SelectionSuggestionPanel` register at high priority when their panels are visible and deregister on dismiss.
