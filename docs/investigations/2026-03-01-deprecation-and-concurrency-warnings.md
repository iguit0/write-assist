# Investigation: Deprecation + Concurrency Warnings

## Summary
Deprecated trust API used for TLS pinning and redundant concurrency annotation on a Sendable lock caused warnings. Updated pinning to use `SecTrustCopyCertificateChain` and removed `nonisolated(unsafe)` from the NSLock constant.

## Symptoms
- `SecTrustGetCertificateAtIndex` deprecated in macOS 12.0 at `CloudAIService.swift:43`
- `nonisolated(unsafe)` unnecessary for `NSLock` constant at `NLAnalysisService.swift:66`

## Investigation Log

### 2026-03-01 - Phase 1/2: Context Builder
**Hypothesis:** TLS pinning uses deprecated trust API; NLAnalysisService lock annotation is redundant.
**Findings:** Context builder confirms pinning via `CloudAIPinning.trustMatchesPins(host:trust:)` and cached NLP objects guarded by `NSLock`.
**Evidence:** `Sources/CloudAIService.swift`, `Sources/NLAnalysisService.swift`, `issues/017-...`, `issues/027-...`
**Conclusion:** Confirmed; proceed to code change.

### 2026-03-01 - Phase 4: Evidence + Fixes
**Hypothesis:** Replace trust chain API with `SecTrustCopyCertificateChain` and drop redundant `nonisolated(unsafe)` on `NSLock`.
**Findings:** `trustMatchesPins` enumerated trust certs via `SecTrustGetCertificateAtIndex`. `nlLock` is `NSLock`, which is `Sendable`, so annotation is unnecessary.
**Evidence:** `Sources/CloudAIService.swift:38-52`, `Sources/NLAnalysisService.swift:63-69`
**Conclusion:** Implemented updates in both files.

## Root Cause
- TLS pinning relied on deprecated `SecTrustGetCertificateAtIndex`, which is flagged on macOS 12+.
- `nonisolated(unsafe)` was applied to a `Sendable` static `NSLock`, so the compiler warned it was redundant.

## Recommendations
1. Use `SecTrustCopyCertificateChain` when iterating trust certificates; keep chain-wide hash matching.
2. Remove `nonisolated(unsafe)` from `NSLock` constants; keep it only on non-Sendable NLP objects.

## Preventive Measures
- Add a quick lint step or build setting to surface deprecation warnings early on security-related APIs.
- Periodically review pinned-certificate code when updating deployment targets.
