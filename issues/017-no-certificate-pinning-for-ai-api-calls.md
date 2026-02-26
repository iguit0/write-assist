# No certificate pinning for Anthropic/OpenAI API calls

**Labels:** `security` `P1-high`  
**Status:** 🆕 New

## Description

All HTTPS requests to `api.anthropic.com` and `api.openai.com` use the system's default `URLSession` trust evaluation without certificate pinning. A compromised certificate authority or a MITM attacker on the network could intercept both the user's API keys and the text being sent for analysis.

This is a meaningful risk for users on corporate or public networks where TLS interception proxies are common.

## Affected Files

- `Sources/CloudAIService.swift` — `callAnthropic(_:)`, `callOpenAI(_:)`, `URLSession.shared` usage

## Proposed Fix

**Option A (recommended for shipping):** Document the tradeoff clearly in the README and in the Settings UI near the API key fields. Note that all AI traffic uses TLS but without pinning.

**Option B (higher security):** Implement `URLSessionDelegate.urlSession(_:didReceive:completionHandler:)` with SHA-256 hash pinning for the known leaf or intermediate certificates of `api.anthropic.com` and `api.openai.com`. Note that certificate rotation requires an app update.

**Option C (pragmatic middle ground):** Use App Transport Security (ATS) configuration in `Info.plist` to explicitly require TLS 1.3 for the AI API domains, reducing the MITM attack surface without the maintenance burden of certificate pinning.

## Additional Context

Since this is a menu bar app without a sandbox (required for global key monitoring), the risk surface is higher than for typical sandboxed Mac apps.
