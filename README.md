# ✏️ WriteAssist

A lightweight, **offline** macOS menu-bar writing assistant that detects spelling and grammar issues system-wide — in any app you type in.

WriteAssist lives entirely in your menu bar. It monitors keystrokes across all applications, runs spell and grammar checks using macOS's built-in `NSSpellChecker`, and shows correction suggestions inline near your text cursor — no windows, no Dock icon, no data ever leaving your device.

---

## Features

- **System-wide monitoring** — works in Mail, Notes, Safari, VS Code, Slack, and every other app
- **Inline suggestion popup** — a floating HUD appears near your cursor when an issue is detected (Grammarly-style)
- **Menu bar sidebar** — click the pencil icon to see all detected issues, a text preview, word count, and a writing score
- **One-click corrections** — suggestions are applied in-place via the Accessibility API; no copy-paste required
- **100% offline** — uses `NSSpellChecker` with no network calls, no telemetry, no third-party services
- **Live badge** — the menu bar icon shows a red badge with the active issue count and flashes when new errors arrive
- **Writing score** — a 0–100 score (spelling errors −5 pts, grammar −3 pts) displayed as a circular progress ring

## Requirements

| Requirement | Minimum |
|---|---|
| macOS | 15 Sequoia |
| Swift toolchain | 6.0 (Xcode 16+) |
| Accessibility permission | Required — see [Granting Access](#granting-accessibility-access) |

No external dependencies. The project uses Swift Package Manager with a single executable target.

## Build & Run

### Terminal (SPM)

```bash
git clone <repo-url> && cd WriteAssist
swift build          # compile
swift run            # build and launch
```

### Xcode

1. **File → Open…** → select the `WriteAssist` directory
2. Xcode recognises `Package.swift` automatically
3. Select the **WriteAssist** scheme and press **⌘R**

> **Note:** Because the app sets its activation policy to `.accessory`, it will not appear in the Dock. Look for the **pencil icon** (✏️) in the menu bar after launching.

## Granting Accessibility Access

WriteAssist requires the **Accessibility** permission to:

- Monitor keystrokes globally (`NSEvent.addGlobalMonitorForEvents`)
- Read the focused text field and caret position via the Accessibility API
- Apply corrections in-place by selecting and replacing text in the target app

### Steps

1. Launch the app (`swift run` or from Xcode).
2. Click the **pencil icon** in the menu bar.
3. The popover displays an **"Accessibility Access Required"** prompt with an **Enable Access** button.
4. Click it — **System Settings → Privacy & Security → Accessibility** opens automatically.
5. Find and toggle **WriteAssist** on.
6. The app detects the permission change within ~3 seconds and begins monitoring.

If you revoke permission later, monitoring stops automatically and the prompt reappears.

> **Tip:** When running via `swift run`, the entry in System Settings may appear as the Swift toolchain binary rather than "WriteAssist". Grant access to whichever entry appears after launching.

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  Any macOS App (Mail, Notes, Safari, etc.)                  │
│  ┌───────────────────────────────────────────────┐          │
│  │  User types text                              │          │
│  └──────────────────┬────────────────────────────┘          │
└─────────────────────┼───────────────────────────────────────┘
                      │ keystrokes (global event monitor)
                      ▼
            ┌─────────────────────┐
            │ GlobalInputMonitor  │  500-char rolling buffer
            └────────┬────────────┘
                     │ textDidChange(_:)
                     ▼
            ┌─────────────────────┐     200 ms debounce
            │ DocumentViewModel   │ ◄── MVVM hub
            └────────┬────────────┘
                     │ check(text:)
                     ▼
            ┌─────────────────────┐     800 ms timeout guard
            │ SpellCheckService   │ ◄── NSSpellChecker (offline)
            └────────┬────────────┘
                     │ [WritingIssue]
                     ▼
       ┌─────────────┴─────────────┐
       │                           │
       ▼                           ▼
┌──────────────┐          ┌────────────────┐
│ ErrorHUDPanel│          │ StatusBar      │
│ (inline HUD) │          │ Popover        │
│ near cursor  │          │ (sidebar)      │
└──────────────┘          └────────────────┘
```

1. **GlobalInputMonitor** captures every keystroke via a global `NSEvent` monitor and accumulates them in a 500-character rolling buffer.
2. **DocumentViewModel** debounces changes (200 ms) and dispatches a spell/grammar check.
3. **SpellCheckService** wraps `NSSpellChecker.checkString` with an 800 ms timeout to guard against XPC stalls.
4. Detected issues surface in two places:
   - **ErrorHUDPanel** — a floating, non-activating `NSPanel` positioned near the text caret (queried via the Accessibility API). Shows the issue type, up to 4 suggestions, and Ignore/dismiss buttons.
   - **Menu bar popover** — a sidebar with all issues, a highlighted text preview, word count, and writing score.
5. When the user clicks a suggestion, **DocumentViewModel** applies the correction in-place using `AXUIElementSetAttributeValue`. If the Accessibility write fails or times out, it falls back to clipboard + synthetic Cmd+V.

## Project Structure

```
WriteAssist/
├── Sources/
│   ├── WriteAssistApp.swift        # @main entry point, AppDelegate
│   ├── GlobalInputMonitor.swift    # System-wide keystroke capture
│   ├── DocumentViewModel.swift     # MVVM state, spell-check scheduling, AX corrections
│   ├── SpellCheckService.swift     # NSSpellChecker async wrapper
│   ├── StatusBarController.swift   # NSStatusItem, popover, badge, icon animation
│   ├── ErrorHUDPanel.swift         # Floating inline suggestion HUD
│   ├── ContentView.swift           # MenuBarPopoverView, IssueSidebarCard, ScoreBadge
│   ├── HighlightedTextView.swift   # NSTextView wrapper for issue underlines
│   └── WritingIssue.swift          # Issue model (type, range, word, suggestions)
├── Package.swift                   # SPM manifest — macOS 15, Swift 6, no deps
├── .swiftlint.yml                  # SwiftLint configuration
└── LICENSE
```

## Privacy

**All processing happens locally on your Mac.** WriteAssist uses only `NSSpellChecker`, which runs entirely on-device via a system XPC service. No text is transmitted over the network, no analytics are collected, and no third-party services are contacted.

## Linting

The project ships with a SwiftLint configuration. Run:

```bash
swiftlint
```

## License

See [LICENSE](LICENSE) for details.
