# `WritingStatsStore` serialises 90 days of session history to `UserDefaults`

**Labels:** `performance` `P3-low`  
**Status:** 🆕 New

## Description

`WritingStatsStore` stores up to 90 days of `WritingSession` objects serialised as JSON arrays in `UserDefaults`. A prolific writer using WriteAssist daily for 90 days accumulates 90+ session objects. Each session includes word count history arrays (one entry per `recordWordCount` call — potentially hundreds per session). This can result in `UserDefaults` entries in the 100 KB–1 MB range.

`UserDefaults` reads and writes the entire plist file synchronously on the main thread. A large history can cause noticeable lag on app launch (during the `init` of `WritingStatsStore`) and on each session update.

## Affected Files

- `Sources/WritingStatsStore.swift`

## Proposed Fix

**Option A (quick win):** Cap session history at 30 sessions instead of 90 days. Most writing statistics dashboards show 30-day trends. This reduces worst-case storage by 3×.

**Option B (correct fix):** Migrate to a lightweight SQLite database (e.g., using `GRDB.swift` or a plain `SQLite3` wrapper) or to a flat JSON file in `Application Support`. Use async file I/O so history reads/writes don't block the main thread.

**Option C (medium effort):** Store only aggregate statistics per day (total words, total sessions, average readability score) rather than raw per-check word counts. This caps the per-day storage to a fixed size regardless of activity level.
