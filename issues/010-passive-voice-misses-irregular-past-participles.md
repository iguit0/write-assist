# Passive voice detection misses irregular past participles and multi-word auxiliaries

**Labels:** `bug` `P1-high`  
**Status:** 🔧 In Progress — see `docs/plans/2026-02-22-passive-voice-detection-plan.md`

## Description

`PassiveVoiceRule` only detects passive voice when the past participle ends in `-ed` (or `-en`/`-wn`/`-ne` via suffix). It misses ~150 common irregular past participles: `taught`, `built`, `kept`, `held`, `found`, `told`, `sold`, etc. Common passive constructions like:

- *"The bridge has been built."* — misses `built`
- *"The lesson was taught by the teacher."* — misses `taught`
- *"She was kept waiting."* — misses `kept`

Additionally, multi-word auxiliary chains like `has been written` and `could be kept` are not matched because the detection loop tries to match multi-word strings against single NLTagger tokens.

## Affected Files

- `Sources/WritingRules/PassiveVoiceRule.swift`

## Proposed Fix

See `docs/plans/2026-02-22-passive-voice-detection-plan.md` for the complete implementation:

1. Add a static `Set<String>` of ~150 irregular past participles.
2. Rewrite the detection loop to walk tokens sequentially, handling auxiliary chains (`has` → `been` → participle) instead of pattern-matching multi-word strings.
