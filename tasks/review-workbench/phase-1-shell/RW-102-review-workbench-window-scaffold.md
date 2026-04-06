# RW-102 — Scaffold the main review workbench window

## Phase
Phase 1 — Shell

## Owner
Workbench UI / shell agent

## Goal
Create the primary review window scaffold that will eventually host editor, grouped review results, inspector, and rewrite compare UI.

## In scope
Add:
- `Sources/ReviewWindow/ReviewWorkbenchView.swift`
- `Sources/ReviewWindow/ReviewWorkbenchLayout.swift`

## Required layout intent
Use a stable review-window composition, not a menu-bar popover clone.

Recommended regions:
- left: review outline/sidebar
- center: editor
- right: inspector / compare panel

Use `NavigationSplitView`, `HSplitView`, or another stable macOS-appropriate layout.

## Requirements
- The scaffold must bind to `ReviewSessionStore` and `RewriteSessionStore`.
- The scaffold must compile before the detailed child views are fully implemented.
- The scaffold must be review-first, not accessory-popover-first.

## Out of scope
- No real editor bridge yet
- No grouped result rendering yet
- No rewrite compare logic yet

## Dependencies
- RW-003
- RW-101

## Acceptance criteria
- [ ] The new workbench view files compile.
- [ ] The review window can render as a primary app surface.
- [ ] The layout clearly supports editor + sidebar + inspector/compare regions.
- [ ] No legacy popover files are repurposed in place.

## Coordination notes
- Do not retrofit `ContentView.swift` into the main workbench surface.
- New files only.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
