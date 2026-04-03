// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import NaturalLanguage

public enum DetectedTone: String, Sendable {
    case confident = "Confident"
    case tentative = "Tentative"
    case formal = "Formal"
    case casual = "Casual"
    case friendly = "Friendly"
    case neutral = "Neutral"

    var icon: String {
        switch self {
        case .confident:  return "hand.thumbsup.fill"
        case .tentative:  return "questionmark.circle"
        case .formal:     return "briefcase.fill"
        case .casual:     return "face.smiling"
        case .friendly:   return "heart.fill"
        case .neutral:    return "minus.circle"
        }
    }
}

struct NLAnalysis: Sendable {
    /// Each element pairs the sentence string with its exact range in the
    /// original text, as reported by NLTokenizer. Use this range in rules
    /// instead of re-searching with text.range(of:) to avoid duplicate-sentence bugs.
    let sentenceRanges: [(sentence: String, range: Range<String.Index>)]
    // Backward-compat accessor — keeps callers that just need the strings working.
    var sentences: [String] { sentenceRanges.map(\.sentence) }
    let words: [String]
    let wordPOSTags: [(word: String, tag: NLTag?, range: Range<String.Index>)]
    let syllableCount: Int
    let wordFrequency: [String: Int]
    let detectedTone: DetectedTone
    let formalityLevel: FormalityLevel
    let audienceLevel: AudienceLevel

    var sentenceCount: Int { max(sentences.count, 1) }
    var wordCount: Int { words.count }
    var averageSentenceLength: Double {
        guard sentenceCount > 0 else { return 0 }
        return Double(wordCount) / Double(sentenceCount)
    }
    var averageWordLength: Double {
        guard wordCount > 0 else { return 0 }
        let totalChars = words.reduce(0) { $0 + $1.count }
        return Double(totalChars) / Double(wordCount)
    }
    var vocabularyDiversity: Double {
        guard wordCount > 0 else { return 0 }
        let uniqueWords = Set(words.map { $0.lowercased() })
        return Double(uniqueWords.count) / Double(wordCount)
    }
}

enum NLAnalysisService {
    // Cached NL processors — allocated once and reused across analysis calls.
    // Allocation cost: 50-200ms on first use (framework lazy-loads CoreNLP models).
    // Protected by `nlLock` because NLTokenizer/NLTagger are not thread-safe.
    // In production, callers use either DocumentViewModel's debounce or DeterministicReviewEngine's Task.detached to ensure non-concurrent access.
    // In tests, the lock prevents concurrent calls from corrupting string indices.
    private static let nlLock = NSLock()
    private nonisolated(unsafe) static let sentenceTokenizer = NLTokenizer(unit: .sentence)
    private nonisolated(unsafe) static let posTagger = NLTagger(tagSchemes: [.lexicalClass])

    static func analyze(
        _ text: String,
        formality: FormalityLevel = .neutral,
        audience: AudienceLevel = .general
    ) -> NLAnalysis {
        let sentenceRanges = tokenizeSentences(text)
        let posTags = tagPartsOfSpeech(text)
        let words = posTags.map(\.word)
        let syllables = countSyllables(words: words)
        let frequency = wordFrequency(words: words)
        let tone = detectTone(text: text, words: words, frequency: frequency)

        return NLAnalysis(
            sentenceRanges: sentenceRanges,
            words: words,
            wordPOSTags: posTags,
            syllableCount: syllables,
            wordFrequency: frequency,
            detectedTone: tone,
            formalityLevel: formality,
            audienceLevel: audience
        )
    }

    // MARK: - Tokenization

    static func tokenizeSentences(_ text: String) -> [(sentence: String, range: Range<String.Index>)] {
        nlLock.lock(); defer { nlLock.unlock() }
        let tokenizer = sentenceTokenizer
        tokenizer.string = text
        var results: [(sentence: String, range: Range<String.Index>)] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                results.append((sentence: sentence, range: range))
            }
            return true
        }
        tokenizer.string = nil // release reference to avoid holding large strings
        return results
    }

    static func tagPartsOfSpeech(_ text: String) -> [(word: String, tag: NLTag?, range: Range<String.Index>)] {
        nlLock.lock(); defer { nlLock.unlock() }
        let tagger = posTagger
        tagger.string = text
        var results: [(word: String, tag: NLTag?, range: Range<String.Index>)] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            results.append((word: String(text[range]), tag: tag, range: range))
            return true
        }
        tagger.string = nil
        return results
    }

    // MARK: - Syllable Counting

    static func countSyllables(word: String) -> Int {
        let lower = word.lowercased()
        guard !lower.isEmpty else { return 0 }

        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var count = 0
        var prevWasVowel = false

        for char in lower {
            let isVowel = vowels.contains(char)
            if isVowel && !prevWasVowel {
                count += 1
            }
            prevWasVowel = isVowel
        }

        // Silent 'e' at the end
        if lower.hasSuffix("e") && count > 1 {
            count -= 1
        }

        // Words like "le" at end add a syllable
        if lower.hasSuffix("le") && lower.count > 2 {
            let beforeLe = lower[lower.index(lower.endIndex, offsetBy: -3)]
            if !vowels.contains(beforeLe) {
                count += 1
            }
        }

        return max(count, 1)
    }

    static func countSyllables(words: [String]) -> Int {
        words.reduce(0) { $0 + countSyllables(word: $1) }
    }

    // MARK: - Word Frequency

    static func wordFrequency(words: [String]) -> [String: Int] {
        var freq: [String: Int] = [:]
        for word in words {
            freq[word.lowercased(), default: 0] += 1
        }
        return freq
    }

    // MARK: - Tone Detection

    private static let hedgingWords: Set<String> = [
        "maybe", "perhaps", "possibly", "probably", "seemingly",
        "basically", "actually", "really", "just", "somewhat",
        "fairly", "rather", "slightly",
    ]

    private static let formalVocabulary: Set<String> = [
        "furthermore", "moreover", "therefore", "consequently", "nevertheless",
        "notwithstanding", "hereby", "henceforth", "aforementioned", "herein",
        "pursuant", "accordingly", "hitherto", "whereby", "wherein",
    ]

    private static let casualVocabulary: Set<String> = [
        "gonna", "wanna", "gotta", "kinda", "sorta", "awesome",
        "cool", "stuff", "yeah", "nope", "hey", "lol", "btw",
    ]

    private static let friendlyWords: Set<String> = [
        "thanks", "thank", "please", "appreciate", "wonderful",
        "great", "love", "happy", "glad", "welcome", "enjoy",
        "hope", "kind", "lovely",
    ]

    static func detectTone(text: String, words: [String], frequency: [String: Int]) -> DetectedTone {
        guard !words.isEmpty else { return .neutral }

        let totalWords = Double(words.count)
        let lowerWords = Set(words.map { $0.lowercased() })

        // Count signals
        let hedgingCount = Double(lowerWords.intersection(hedgingWords).count)
        let formalCount = Double(lowerWords.intersection(formalVocabulary).count)
        let casualCount = Double(lowerWords.intersection(casualVocabulary).count)
        let friendlyCount = Double(lowerWords.intersection(friendlyWords).count)

        // Punctuation signals
        let exclamationCount = Double(text.filter { $0 == "!" }.count)
        let questionCount = Double(text.filter { $0 == "?" }.count)

        // ALL CAPS words (signals shouting/emphasis)
        let capsWords = words.filter { $0.count > 1 && $0 == $0.uppercased() && $0.first?.isLetter == true }
        let capsRatio = Double(capsWords.count) / totalWords

        // Score each tone
        var scores: [DetectedTone: Double] = [
            .confident: 0, .tentative: 0, .formal: 0,
            .casual: 0, .friendly: 0, .neutral: 5,
        ]

        // Hedging -> tentative
        scores[.tentative, default: 0] += hedgingCount * 3

        // Formal vocabulary -> formal
        scores[.formal, default: 0] += formalCount * 4

        // Casual vocabulary -> casual
        scores[.casual, default: 0] += casualCount * 4

        // Friendly words -> friendly
        scores[.friendly, default: 0] += friendlyCount * 3

        // Exclamation marks -> friendly/casual
        scores[.friendly, default: 0] += min(exclamationCount * 2, 8)
        scores[.casual, default: 0] += min(exclamationCount, 4)

        // Lots of questions -> tentative
        scores[.tentative, default: 0] += min(questionCount * 1.5, 6)

        // ALL CAPS -> confident
        scores[.confident, default: 0] += capsRatio * 20

        // Low hedging + declarative sentences -> confident
        if hedgingCount == 0 && exclamationCount == 0 && questionCount == 0 {
            scores[.confident, default: 0] += 3
        }

        // Return the tone with the highest score
        return scores.max(by: { $0.value < $1.value })?.key ?? .neutral
    }
}
