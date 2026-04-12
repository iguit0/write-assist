# ✏️ WriteAssist

A local-first macOS writing assistant built around a **Review Workbench** — an explicit, document-centric review and rewrite workflow.

> **Architecture direction**: WriteAssist has pivoted from a system-wide ambient monitor to a review-first, local-first workbench. See [`tasks/prd-writeassist-review-workbench.md`](tasks/prd-writeassist-review-workbench.md) for the current product requirements.

## What it does

- **Review Workbench** — paste or import text into a dedicated window; run a local spell/grammar/style check; inspect issues by paragraph and sentence; apply deterministic fixes locally.
- **Explicit AI rewrites** — select a sentence or paragraph, choose a rewrite mode (Fix Grammar, Natural, Shorter, Formal), and request a rewrite via Ollama (local) or a configured cloud provider.
- **Review Selection** — one-shot import of selected text from any app via Accessibility API; opens a lightweight review panel first, with the full workspace available when you want deeper editing or rewrites.
- **Local-first** — all passive checks are on-device; cloud AI is invoked only on explicit user request.
- **Loopback-only Ollama** — local model traffic is restricted to `localhost` / loopback.

## Requirements

| Requirement | Minimum |
|---|---|
| macOS | 15 Sequoia |
| Swift toolchain | 6.0 (Xcode 16+) |
| Accessibility permission | Required for **Review Selection** — see [Granting Accessibility Access](#granting-accessibility-access) |

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

WriteAssist needs Accessibility access for the **Review Selection** feature, which imports selected text from the focused application.

### Steps

1. Launch the app from `swift run` or Xcode.
2. Open **System Settings → Privacy & Security → Accessibility**.
3. Enable WriteAssist (or the Swift toolchain binary when using `swift run`).

## How It Works

1. The **menu bar launcher** provides four actions: Review Selection, Open Workspace, Settings, Quit.
2. **Review Selection** is the primary path. It imports the current selection from the focused app via AX, opens a lightweight review panel, and can also be triggered globally with **⌃⌥⌘R**.
3. **Open Workspace** opens the full Review Workbench window directly.
4. The review panel shows a quick, compact issue summary near your current context without forcing a document window.
5. Inside the workbench, **DeterministicReviewEngine** runs a local spell + grammar + style pipeline.
5. **ReviewGrouping** organises results by paragraph and sentence.
6. **ReviewSessionStore** owns the document, analysis lifecycle, selection state, and the single local mutation path.
7. **LocalFirstRewriteEngine** rewrites selected text via Ollama first, with optional cloud fallback.

## Privacy & Data Handling

- Spelling, grammar, and style checks stay on-device.
- Text is sent to the configured AI provider only when you explicitly request an AI rewrite.
- API keys for Anthropic and OpenAI are stored in macOS Keychain.
- Cloud AI traffic uses TLS certificate pinning for supported providers.
- Ollama traffic is allowed only to loopback addresses.
- The app suppresses AX inspection for secure input contexts such as password fields.
- Personal dictionary entries, ignore rules, provider/model preferences, and writing stats are stored locally in `UserDefaults`.

## Project Structure

```text
WriteAssist/
├── Sources/
│   ├── App/                        # AppShellController, AppMode, app entry point
│   ├── ReviewDomain/               # ReviewDocument, ReviewAnalysisSnapshot, ReviewSessionStore
│   ├── ReviewServices/             # DeterministicReviewEngine, ReviewGrouping
│   ├── ReviewWindow/               # ReviewWorkbenchView, editor, sidebar, inspector, rewrite UI
│   ├── Rewrite/                    # RewriteSessionStore, LocalFirstRewriteEngine, contracts
│   ├── SystemIntegration/          # SelectionImportService (one-shot AX import)
│   ├── SpellCheckService.swift
│   ├── NLAnalysisService.swift
│   ├── RuleEngine.swift
│   ├── WritingRules/               # individual rule implementations
│   └── [legacy inline-monitor files — non-primary, see note below]
├── docs/
│   ├── architecture/               # target architecture
│   └── plans/                      # migration and implementation plans
├── tasks/
│   ├── prd-writeassist-review-workbench.md   # current PRD
│   └── review-workbench/                     # implementation tickets (RW-001 … RW-602)
├── Package.swift
└── LICENSE
```

> **Legacy note**: `GlobalInputMonitor`, `SelectionMonitor`, `ExternalSpellChecker`, `ErrorHUDPanel`, `SelectionSuggestionPanel`, `UndoToastPanel`, and related files represent the old ambient inline-monitor path. They are kept compilable for reference but are no longer the primary product surface. The app boots in `reviewWorkbenchOnly` mode by default.

## Source-of-truth docs

- [`tasks/prd-writeassist-review-workbench.md`](tasks/prd-writeassist-review-workbench.md) — product requirements
- [`docs/architecture/review-workbench-target-architecture.md`](docs/architecture/review-workbench-target-architecture.md) — target architecture
- [`docs/plans/review-workbench-migration-plan.md`](docs/plans/review-workbench-migration-plan.md) — migration plan
- [`tasks/review-workbench/README.md`](tasks/review-workbench/README.md) — implementation ticket index

## Linting

```bash
swiftlint
```

## License

See [LICENSE](LICENSE) for details.
