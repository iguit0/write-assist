# ✏️ WriteAssist

A local-first macOS menu-bar writing assistant for system-wide spelling, grammar, and rewrite workflows.

WriteAssist lives in your menu bar, monitors typing across apps with Accessibility permission, runs passive spelling and grammar checks locally, and can optionally generate AI rewrites when you explicitly ask for them.

## Features

- **Local-first passive checks** — background spelling and grammar detection stays on-device.
- **System-wide monitoring** — works in Mail, Notes, Safari, VS Code, Slack, and other text apps.
- **Inline suggestion HUD** — a floating panel appears near the caret when local issues are detected.
- **Explicit AI rewrites** — cloud or Ollama rewrites run only after you click a rewrite control.
- **Loopback-only Ollama** — local model traffic is restricted to `localhost` / loopback.
- **Menu bar sidebar** — inspect issues, preview text, view stats, and request suggestions from the popover.

## Requirements

| Requirement | Minimum |
|---|---|
| macOS | 15 Sequoia |
| Swift toolchain | 6.0 (Xcode 16+) |
| Accessibility permission | Required — see [Granting Accessibility Access](#granting-accessibility-access) |

No external package dependencies. The project uses Swift Package Manager with a core library target plus a thin app target.

## Build & Run

### Terminal (SPM)

```bash
git clone <repo-url> && cd WriteAssist
swift build
swift run
```

### Xcode

1. Open the `WriteAssist` directory in Xcode.
2. Let Xcode resolve `Package.swift`.
3. Select the `WriteAssist` scheme and run.

Because the app uses `.accessory` activation policy, it does not appear in the Dock. Look for the pencil icon in the menu bar after launch.

## Granting Accessibility Access

WriteAssist needs Accessibility access to:

- monitor keystrokes globally
- inspect focused text fields and selections
- apply corrections directly in the target app

### Steps

1. Launch the app from `swift run` or Xcode.
2. Click the menu bar icon.
3. Use the **Enable Access** button in the popover.
4. In **System Settings → Privacy & Security → Accessibility**, enable WriteAssist.
5. Return to the app. It detects permission changes automatically.

If permission is revoked later, monitoring stops automatically.

> When running with `swift run`, the entry in System Settings may appear as the Swift toolchain binary instead of `WriteAssist`.

## How It Works

1. **GlobalInputMonitor** captures keystrokes into a rolling buffer for passive local checks.
2. **DocumentViewModel** debounces changes and runs local spell / grammar detection.
3. **SpellCheckService** wraps `NSSpellChecker` for local spell checking.
4. **ErrorHUDPanel** surfaces local issues inline near the caret.
5. **SelectionSuggestionPanel** appears when you select enough text, but it does not call AI automatically. A rewrite request is sent only after you click a rewrite style.
6. **DocumentViewModel** applies accepted changes with Accessibility APIs first and falls back to clipboard + synthetic paste only when direct replacement fails.

## Privacy & Data Handling

- Passive spelling and grammar checks stay on-device.
- Selected text is sent to the configured AI provider only when you explicitly request an AI rewrite or suggestion.
- API keys for Anthropic and OpenAI are stored in macOS Keychain.
- Cloud AI traffic uses TLS certificate pinning for supported providers.
- Ollama traffic is allowed only to loopback addresses such as `localhost` and `127.0.0.1`.
- Clipboard fallback may temporarily place replacement text on the macOS pasteboard if AX replacement fails.
- Personal dictionary entries, ignore rules, provider/model preferences, and writing stats are stored locally in `UserDefaults`.
- The app suppresses capture and AX inspection for secure input contexts such as password fields.

## Project Structure

```text
WriteAssist/
├── Sources/
│   ├── App/                       # app entry point
│   ├── AXHelper.swift            # accessibility helpers + secure-context gating
│   ├── DocumentViewModel.swift   # local checks, correction flow, clipboard fallback
│   ├── GlobalInputMonitor.swift  # system-wide keystroke capture
│   ├── SelectionSuggestionPanel.swift
│   ├── SpellCheckService.swift
│   └── WritingRules/
├── Tests/WriteAssistTests/
├── Package.swift
└── LICENSE
```

## Linting

```bash
swiftlint
```

## License

See [LICENSE](LICENSE) for details.
