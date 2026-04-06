# RW-002 — Freeze rewrite and selection-import contracts

## Phase
Phase 0 — Foundation

## Owner
Rewrite / system-integration architecture agent

## Goal
Define the request/response contracts for explicit rewrite and one-shot selection import before UI or service work starts.

## In scope
Add these files:
- `Sources/Rewrite/RewriteMode.swift`
- `Sources/Rewrite/RewriteRequest.swift`
- `Sources/Rewrite/RewriteCandidate.swift`
- `Sources/Rewrite/RewriteEngine.swift`
- `Sources/Rewrite/RewriteProviderPolicy.swift`
- `Sources/SystemIntegration/SelectionImporting.swift`
- `Sources/SystemIntegration/SelectionImportError.swift`

## Required contracts

### Rewrite
- `RewriteMode`
  - `.grammarFix`
  - `.natural`
  - `.shorter`
  - `.formal`
- `RewriteTarget`
  - `.sentence(id: String, range: NSRange)`
  - `.paragraph(id: String, range: NSRange)`
  - `.customSelection(range: NSRange)`
- `RewriteProviderPolicy`
  - `primary: AIProvider`
  - `fallback: AIProvider?`
- `RewriteRequest`
  - `id: UUID`
  - `documentID: UUID`
  - `documentRevision: Int`
  - `target: RewriteTarget`
  - `sourceText: String`
  - `mode: RewriteMode`
  - `providerPolicy: RewriteProviderPolicy`
- `RewriteCandidate`
  - `id: UUID`
  - `provider: AIProvider`
  - `modelName: String`
  - `text: String`
- `RewriteResult`
  - `requestID: UUID`
  - `candidates: [RewriteCandidate]`
- `RewriteEngine`
  - `func rewrite(_ request: RewriteRequest) async throws -> RewriteResult`

### Selection import
- `SelectionImporting`
  - `func importCurrentSelection() async throws -> ImportedSelection`
- `ImportedSelection`
  - `text: String`
  - `metadata: ImportedSelectionMetadata`
- `SelectionImportError`
  - `.accessibilityDenied`
  - `.secureContext`
  - `.noFocusedElement`
  - `.noSelection`
  - `.unsupportedElement`

## Out of scope
- No AI implementation
- No selection import AX implementation
- No UI

## Dependencies
- RW-001

## Acceptance criteria
- [ ] Rewrite contracts compile and are `Sendable` where appropriate.
- [ ] Selection import contracts compile and reuse `ImportedSelectionMetadata` from the review domain.
- [ ] `documentRevision` is part of rewrite requests.
- [ ] No ambient/global-monitor assumptions leak into these contracts.

## Coordination notes
- Do not edit `CloudAIService.swift` yet.
- Do not add fallback heuristics or provider logic yet.
- Freeze shapes only.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
