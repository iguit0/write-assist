# `HedgingRule` causes alert fatigue — flags "just", "really", "actually" in every message

**Labels:** `bug` `ux` `P2-medium`  
**Status:** 🆕 New

## Description

`HedgingRule` flags common conversational words as hedging language:

```swift
let hedgingPhrases = [
    "just", "actually", "really", "basically", "honestly",
    "kind of", "sort of", "I think", "I believe", "I feel like",
    // ...
]
```

Words like "just", "actually", "really", and "basically" appear in virtually every casual email, Slack message, or document. A user composing a short note like *"I just wanted to follow up on this"* will immediately see a hedging warning on "just". Because these fire so frequently, users quickly learn to dismiss all HUD suggestions — including legitimate spelling and grammar errors. This is textbook alert fatigue.

## Proposed Fix

**Option A (recommended):** Separate the phrase list into two tiers:

- **High-signal hedges** (keep as active flags): "I think", "I believe", "I feel like", "kind of", "sort of" — these are meaningful when used habitually
- **Low-signal filler words** (move to opt-in or suppress by default): "just", "really", "actually", "basically", "honestly"

**Option B:** Apply context sensitivity — only flag "just", "really", "actually" when they appear at the **start of a sentence** or **more than once in a paragraph**, indicating habitual use.

**Option C:** Add a "writing mode" preference (Casual / Professional / Academic) and only apply the full hedging rule in Professional/Academic mode.

## Additional Context

Tools like Hemingway App and ProWritingAid suppress or de-emphasise single-occurrence filler words and only flag patterns of overuse. The current all-or-nothing approach is not calibrated to casual writing.
