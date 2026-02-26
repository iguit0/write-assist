# `NLTagger` and `NLTokenizer` recreated on every analysis call

**Labels:** `performance` `P2-medium`  
**Status:** 🆕 New

## Description

`NLAnalysisService.analyze` creates fresh `NLTokenizer` (×2) and `NLTagger` instances on every call. `NLTagger` in particular loads a language model from disk/memory on creation, which takes significant time. At a 0.2 s debounce rate, these objects are created up to 5× per second during fast typing.

```swift
// NLAnalysisService.swift — called on every check
func analyze(text: String) -> NLAnalysis {
    let tokenizer = NLTokenizer(unit: .word)      // created fresh
    let sentenceTokenizer = NLTokenizer(unit: .sentence)  // created fresh
    let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])  // expensive
    // ...
}
```

## Affected Files

- `Sources/NLAnalysisService.swift` — `analyze(text:)` method, approximately lines 63–70

## Proposed Fix

Cache the tokenizer and tagger instances across calls. Since `NLAnalysisService` is currently a namespace (`enum`), either convert it to a `class` with instance properties or use `static let` cached instances:

```swift
enum NLAnalysisService {
    // Cached instances — created once, reused on every analyze call
    private static let wordTokenizer: NLTokenizer = {
        NLTokenizer(unit: .word)
    }()
    private static let sentenceTokenizer: NLTokenizer = {
        NLTokenizer(unit: .sentence)
    }()
    private static let tagger: NLTagger = {
        NLTagger(tagSchemes: [.lexicalClass, .nameType])
    }()
    
    static func analyze(text: String) -> NLAnalysis {
        wordTokenizer.string = text
        sentenceTokenizer.string = text
        tagger.string = text
        // ... rest unchanged
    }
}
```

`NLTokenizer` and `NLTagger` are safe to reuse by reassigning `.string` between calls.

## Additional Context

This fix compounds with issue [002](002-nl-analysis-blocks-main-actor.md) — moving analysis off-actor is more impactful, but caching the instances further reduces per-call overhead.
