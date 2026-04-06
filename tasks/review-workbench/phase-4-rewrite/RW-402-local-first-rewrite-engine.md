# RW-402 — Build local-first rewrite engine and provider policy

## Phase
Phase 4 — Rewrite

## Owner
Rewrite engine agent

## Goal
Implement explicit local-first rewrite execution with optional cloud fallback.

## In scope
Add:
- `Sources/Rewrite/LocalFirstRewriteEngine.swift`

Update as needed:
- `Sources/CloudAIService.swift`
- `Sources/OllamaService.swift`
- `Sources/AIPromptTemplates.swift`
- `Sources/SettingsPanel.swift`

## Required provider behavior
Order of execution:
1. Ollama/local provider when configured and reachable
2. optional cloud fallback if enabled
3. user-facing failure if neither path succeeds

## Required API direction
Move toward request-scoped completion behavior.
Avoid keeping rewrite correctness tied to one mutable global active request lane.

## Out of scope
- No compare UI here
- No shell/startup edits

## Dependencies
- RW-401

## Acceptance criteria
- [ ] Local-first rewrite engine compiles.
- [ ] Sentence rewrite requests can execute through local-first provider policy.
- [ ] Optional cloud fallback works only when explicitly configured.
- [ ] Provider/model information can be surfaced to UI consumers.
- [ ] No ambient per-keystroke AI behavior is introduced.

## Coordination notes
- Single-owner file: `Sources/CloudAIService.swift`
- Single-owner file: `Sources/SettingsPanel.swift`
- Do not let this turn into a general startup/menu bar change ticket.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
