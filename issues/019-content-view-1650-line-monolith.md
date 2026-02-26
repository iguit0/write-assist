# `ContentView.swift` is a 1650-line monolith causing broad re-renders

**Labels:** `refactor` `performance` `P2-medium`  
**Status:** 🆕 New

## Description

`ContentView.swift` at 1650 lines contains the entire popover UI: header, tab bar, Issues list, individual issue cards, Tools panel, Settings panel, Chat panel, Statistics panel, and all Preferences sub-views. This creates two problems:

1. **Maintenance:** a single file change touches the entire UI, making code review and collaboration harder.
2. **Performance:** because all views observe the same `DocumentViewModel` `@Observable` object from a single body scope, any property change on the view model (even unrelated to the current tab) can trigger re-evaluation of the entire 1650-line view tree. This is a classic SwiftUI view invalidation storm.

## Affected Files

- `Sources/ContentView.swift` (1650 lines)

## Proposed Refactoring

Split into per-feature files with focused observation scopes:

| New File | Contents |
|----------|----------|
| `IssuesListView.swift` | Issue cards, category filter bar |
| `IssueCardView.swift` | Individual issue row with correction buttons |
| `ToolsPanel.swift` | Snippets and Tools tab content |
| `SettingsPanel.swift` | Settings and Preferences tab content |
| `ChatPanel.swift` | AI chat interface |
| `WritingStatsView.swift` | Statistics and readability metrics |

Each sub-view should accept only the specific `@Observable` slice it needs (or use `@Bindable` on a sub-model) so that changes to unrelated properties do not trigger its `body`.

## Additional Context

Per the SwiftUI performance audit skill: *"Broad dependencies in observable models"* is a top-tier cause of view invalidation storms. `@Observable` tracks property access within `body` — if `body` is huge, nearly any property mutation re-evaluates the whole tree.
