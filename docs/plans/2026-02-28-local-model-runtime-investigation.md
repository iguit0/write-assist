# Investigation: Local Model Runtime Logs

## Summary
Runtime logs are a mix of app-level guardrails (AX permission gating and Ollama reachability) and system/framework warnings likely caused by running the SPM executable (even via Xcode) without a bundled identifier. Connection-refused logs point to IPv6 loopback (`::1`) not being listened on by the local Ollama server.

## Symptoms
- Cannot index window tabs due to missing main bundle identifier
- SelectionMonitor: AX permission not granted — skipping start
- Global hotkey registered: Cmd+Shift+G
- flock failed to lock list file (/var/folders/.../com.apple.metal/.../libraries.list): errno = 35
- nw_socket_handle_socket_event Socket SO_ERROR [61: Connection refused]
- nw_endpoint_flow_failed_with_error [::1:11434] already failing, returning

## Investigation Log

### 2026-02-28 - Initial Assessment
**Hypothesis:** Errors originate from a mix of app-level permission gating and system/runtime noise caused by bundle-less execution and missing local model server.
**Findings:**
- `SelectionMonitor.start()` logs the AX-permission skip when `AXIsProcessTrusted()` is false; this explains the "SelectionMonitor: AX permission not granted — skipping start" line.
- `StatusBarController.registerGlobalHotkey()` logs the "Global hotkey registered: Cmd+Shift+G" message after installing the global monitor.
- `OllamaService.performRequest` maps connection errors to `CloudAIError.ollamaNotRunning`, matching the network framework connection-refused logs when Ollama isn’t running.
- `README` warns that when launched via `swift run`, the app’s identity in Accessibility settings may show the Swift toolchain binary instead of WriteAssist, consistent with a missing bundle identifier warning.
**Evidence:** `Sources/SelectionMonitor.swift:45-67`, `Sources/StatusBarController.swift:380-395`, `Sources/OllamaService.swift:150-190`, `Sources/CloudAIService.swift:116-196`, `README.md:52-92`.
**Conclusion:** App-level logs are accounted for; remaining warnings appear to be system/framework logs from bundle-less execution and local-model runtime. Additional validation needed.

### 2026-02-28 - Log Line Mapping
**Hypothesis:** Each log line can be attributed to either a specific app logger or system framework.
**Findings:**
- "SelectionMonitor: AX permission not granted — skipping start" is from `SelectionMonitor.start()` and indicates AX access is not yet granted.
- "Global hotkey registered: Cmd+Shift+G" is from `StatusBarController.registerGlobalHotkey()` and is benign.
- Connection refused to `::1:11434` matches `OllamaService.performRequest` handling when Ollama is not running or bound to localhost.
- "Cannot index window tabs due to missing main bundle identifier" does not appear in app code; likely emitted by AppKit or system frameworks when running via `swift run` without an app bundle.
- Metal `flock` lockfile warnings are also external to the app and likely from Metal shader cache contention during local-model runtime.
**Evidence:** `Sources/SelectionMonitor.swift:45-67`, `Sources/StatusBarController.swift:380-395`, `Sources/OllamaService.swift:150-190`, `README.md:52-92`.
**Conclusion:** Primary actionable items are ensuring AX permission and Ollama server availability; bundle identifier and Metal logs are likely benign in this context.

### 2026-02-28 - Potential App Bug
**Hypothesis:** Selection monitoring does not restart after Accessibility permission is granted.
**Findings:** `SelectionMonitor.start()` is called once in `StatusBarController.setup()` and does not appear to be re-invoked on permission changes. Meanwhile, `GlobalInputMonitor` polls every 3 seconds to start itself when permission is granted, but does not restart `SelectionMonitor`.
**Evidence:** `Sources/StatusBarController.swift:105-175`, `Sources/SelectionMonitor.swift:45-67`, `Sources/GlobalInputMonitor.swift:60-104`.
**Conclusion:** Likely bug: selection-based features will stay disabled until relaunch if permission is granted after launch.
## Root Cause
The observed log lines are a **combination of expected app-level guardrails and external system/framework warnings**, not a single crash-level bug:

- When running via Xcode with an SPM executable target, the process still lacks a bundle identifier, so macOS logs bundle-identifier warnings (like window tab indexing) even though the app is menu-bar only.
- Ollama connection failures appear to be IPv6 loopback (`::1`) connection refusals, which can happen if Ollama is bound to `127.0.0.1` only. `localhost` may resolve to `::1` first on macOS.

1. **Missing bundle identifier warning** is emitted by AppKit/system frameworks when the app is launched via `swift run` (SPM executable) rather than a bundled `.app`. There is no bundle identifier in this launch context, so features that rely on it (like window tab indexing) log warnings even though WriteAssist has no windows. Evidence: README explicitly notes that `swift run` launch can change the system identity shown in Accessibility settings, and `StatusBarController` contains fallback logic for bundle-less runs when SF Symbols fail to resolve.
2. **SelectionMonitor permission log** is a direct guard in `SelectionMonitor.start()` when `AXIsProcessTrusted()` is false. This is expected if Accessibility permission is not granted at launch; it is not inherently an error, but it means selection-based panels will not run.
3. **Connection refused to ::1:11434** is consistent with Ollama not running or not bound to localhost. `OllamaService.performRequest` maps `.cannotConnectToHost` / `.cannotFindHost` to `CloudAIError.ollamaNotRunning`.
4. **Metal lockfile warning** is a system-level log likely caused by Metal shader cache lock contention, possibly from multiple GPU-using processes (e.g., a local model using Metal). There is no project source reference to this path; likely benign unless accompanied by functional failures.

## Recommendations
1. **Confirm launch context and bundle identity**: If running via `swift run`, expect bundle-id warnings. For clean runs and proper system identity, launch from Xcode or a built `.app` bundle. This also makes the Accessibility entry appear as “WriteAssist.”
2. **Ensure AX permissions are granted to the correct binary**: In System Settings → Privacy & Security → Accessibility, enable the entry that appears after launch (often the Swift toolchain when using `swift run`). This resolves the SelectionMonitor skip log and enables selection-based features.
3. **Prefer IPv4 loopback if Ollama only binds to 127.0.0.1**: Set the server URL to `http://127.0.0.1:11434` or implement a localhost→IPv4 fallback to avoid IPv6 `::1` connection refusals.
4. **Fix selection-monitor restart**: Wire permission-change callbacks to restart `SelectionMonitor` so selection-based UI works without app restart.

## Preventive Measures
- Add a small startup diagnostic banner in the Settings panel summarizing current AX permission state, bundle identity (if available), and Ollama reachability to distinguish benign logs from action items.
- When running via `swift run`, surface a hint in the UI that the Accessibility entry may appear under the Swift toolchain, and provide a “Restart after granting access” prompt if selection monitoring has not restarted.
- Add a lightweight health-check for Ollama on startup to clarify whether the server is reachable before the user triggers a request.
