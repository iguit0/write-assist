# Improved Passive Voice Detection — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix passive voice detection to catch irregular past participles and multi-word auxiliary constructions that are currently missed.

**Architecture:** Single-file modification to `PassiveVoiceRule.swift`. Add an inline `Set<String>` of ~150 irregular past participles. Rewrite the detection loop to walk tokens sequentially, handling auxiliary chains (`has` → `been` → participle) instead of trying to match multi-word strings against single tokens.

**Tech Stack:** Swift, NaturalLanguage framework (NLTag), existing WritingRule protocol

**Design doc:** `docs/plans/2026-02-22-passive-voice-detection-design.md`

---

### Task 1: Add irregular past participle set and `isPastParticiple` helper

**Files:**
- Modify: `Sources/WritingRules/PassiveVoiceRule.swift:12-17` (replace `toBeVerbs` section, add new sets)

**Step 1: Add three static properties**

Replace the existing `toBeVerbs` set (lines 12–17) with these three sets and one helper:

```swift
// Single-word "to be" forms — direct passive auxiliaries
private static let toBeVerbs: Set<String> = [
    "is", "are", "was", "were", "be", "been", "being", "am",
]

// Modal/auxiliary verbs that precede "be/been/being" in passive chains
private static let auxiliaryVerbs: Set<String> = [
    "has", "have", "had", "will", "shall",
    "could", "would", "might", "must", "should", "can", "may",
]

// Irregular past participles not caught by the -ed suffix check.
// Sourced from standard English irregular verb tables.
// swiftlint:disable:next identifier_name
private static let irregularPastParticiples: Set<String> = [
    // -ught/-ought
    "taught", "caught", "bought", "brought", "fought", "thought",
    // -elt/-elt
    "felt", "dealt", "dwelt",
    // -ept
    "kept", "slept", "swept", "wept", "crept",
    // -eft
    "left", "bereft",
    // -ent
    "sent", "spent", "lent", "bent", "meant", "went",
    // -ilt
    "built", "spilt",
    // -old/-eld
    "told", "sold", "held",
    // -ood
    "stood", "understood", "withstood",
    // -ound
    "found", "ground", "bound", "wound",
    // -aid
    "paid", "said", "laid",
    // -ade
    "made",
    // irregular -ed (same form as base or different pronunciation)
    "bred", "fed", "led", "bled", "fled", "shed", "sped", "wed", "read",
    // -ung
    "rung", "sung", "clung", "stung", "swung", "wrung", "hung", "flung", "slung", "sprung",
    // -unk
    "drunk", "sunk", "stunk", "shrunk",
    // -un
    "run", "spun", "won", "begun",
    // -um
    "swum",
    // -at/-ot/-ut/-it/-et
    "sat", "shot", "got", "cut", "put", "shut", "hit", "lit", "knit", "spit", "split",
    "quit", "set", "met", "bet",
    // -urt/-ost/-uck/-ug/-id/-ad
    "hurt", "lost", "cost", "stuck", "struck", "dug", "slid", "hid", "rid", "bid",
    "had", "spread",
    // unique/other
    "come", "become", "let", "burst", "cast", "forecast",
    // -en forms (already caught by suffix but included for completeness)
    "written", "taken", "spoken", "broken", "chosen", "driven", "risen", "ridden",
    "hidden", "bitten", "eaten", "fallen", "forgotten", "forgiven", "given", "frozen",
    "shaken", "stolen", "woken", "awoken", "arisen", "beaten", "forbidden",
    // -wn forms (already caught by suffix but included for completeness)
    "drawn", "blown", "flown", "grown", "known", "shown", "sown", "sewn",
    "mown", "thrown", "sworn", "worn", "torn", "withdrawn",
    // -ne forms
    "done", "gone", "borne",
]

private static func isPastParticiple(_ word: String) -> Bool {
    word.hasSuffix("ed") || irregularPastParticiples.contains(word)
}
```

**Step 2: Build and lint**

Run: `swift build 2>&1 | tail -5`
Expected: Build Succeeded, zero errors/warnings

Run: `swiftlint --path Sources/WritingRules/PassiveVoiceRule.swift`
Expected: zero violations

**Step 3: Commit**

```bash
git add Sources/WritingRules/PassiveVoiceRule.swift
git commit -m "feat(passive-voice): add irregular past participle dictionary

Adds ~150 irregular past participles (taught, built, kept, held, etc.)
that were missed by the suffix-only check (-ed/-en/-wn/-ne).
Splits toBeVerbs into single-word to-be forms and auxiliary verbs
in preparation for fixing multi-word auxiliary matching."
```

---

### Task 2: Rewrite detection loop with sequential token walking

**Files:**
- Modify: `Sources/WritingRules/PassiveVoiceRule.swift:19-58` (replace `check` method)

**Step 1: Replace the `check` method**

Replace the entire `check(text:analysis:)` method (lines 19–61) with:

```swift
func check(text: String, analysis: NLAnalysis) -> [WritingIssue] {
    var issues: [WritingIssue] = []
    let tags = analysis.wordPOSTags
    var i = 0

    while i < tags.count {
        let lower = tags[i].word.lowercased()

        if Self.toBeVerbs.contains(lower) {
            // Path 1: direct "to be" verb → [adverb] → past participle
            if let issue = detectPassive(tags: tags, startIdx: i, beIdx: i, text: text) {
                issues.append(issue)
            }
        } else if Self.auxiliaryVerbs.contains(lower) {
            // Path 2: auxiliary → [adverb] → be/been/being → [adverb] → past participle
            var j = i + 1
            // Skip optional adverb after auxiliary
            if j < tags.count, tags[j].tag == .adverb { j += 1 }
            // Expect a "to be" verb next
            if j < tags.count {
                let beCandidate = tags[j].word.lowercased()
                if beCandidate == "be" || beCandidate == "been" || beCandidate == "being" {
                    if let issue = detectPassive(tags: tags, startIdx: i, beIdx: j, text: text) {
                        issues.append(issue)
                    }
                }
            }
        }

        i += 1
    }

    return issues
}

/// Look for a past participle after `beIdx`, skipping one optional adverb.
/// Returns a WritingIssue spanning from `startIdx` to the participle, or nil.
private func detectPassive(
    tags: [(word: String, tag: NLTag?, range: Range<String.Index>)],
    startIdx: Int,
    beIdx: Int,
    text: String
) -> WritingIssue? {
    var nextIdx = beIdx + 1
    // Skip optional adverb between to-be verb and participle
    if nextIdx < tags.count, tags[nextIdx].tag == .adverb { nextIdx += 1 }
    guard nextIdx < tags.count else { return nil }

    let (nextWord, nextTag, _) = tags[nextIdx]
    guard nextTag == .verb else { return nil }
    guard Self.isPastParticiple(nextWord.lowercased()) else { return nil }

    // Build phrase range from start auxiliary/to-be to the participle
    let phraseRange = tags[startIdx].range.lowerBound..<tags[nextIdx].range.upperBound
    let nsRange = NSRange(phraseRange, in: text)
    let phrase = String(text[phraseRange])

    return WritingIssue(
        type: .passiveVoice,
        range: nsRange,
        word: phrase,
        message: "Passive voice — consider using active voice",
        suggestions: []
    )
}
```

**Step 2: Build and lint**

Run: `swift build 2>&1 | tail -5`
Expected: Build Succeeded, zero errors/warnings

Run: `swiftlint --path Sources/WritingRules/PassiveVoiceRule.swift`
Expected: zero violations

**Step 3: Commit**

```bash
git add Sources/WritingRules/PassiveVoiceRule.swift
git commit -m "feat(passive-voice): fix multi-word auxiliary matching

Rewrite detection loop to walk tokens sequentially instead of
matching multi-word strings against single NLTagger tokens.
Handles auxiliary chains like has→been→participle and
could→be→participle that were previously broken."
```

---

### Task 3: Manual verification

**Step 1: Build and run the app**

Run: `swift run`
Expected: App launches in menu bar

**Step 2: Test passive voice detection**

Open any text editor and type each sentence. The HUD should appear for passive constructions:

| Sentence | Expected |
|----------|----------|
| "The report was reviewed by the team." | Flag "was reviewed" |
| "The lesson was taught by the professor." | Flag "was taught" |
| "The bridge has been built." | Flag "has been built" |
| "It could be kept secret." | Flag "could be kept" |
| "The door was quickly shut." | Flag "was quickly shut" |
| "She was running." | NO flag (progressive, not passive) |
| "He writes code." | NO flag (active voice) |
| "They have eaten dinner." | NO flag (active perfect, not passive) |

**Step 3: Final lint check**

Run: `swiftlint`
Expected: zero violations across entire project
