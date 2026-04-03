// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

public struct DocumentIssueSummary: Sendable, Equatable {
    public let spelling: Int
    public let grammar: Int
    public let clarity: Int
    public let engagement: Int
    public let delivery: Int
    public let total: Int
}

public struct DocumentMetrics: Sendable, Equatable {
    public let wordCount: Int
    public let characterCount: Int
    public let sentenceCount: Int
    public let averageSentenceLength: Double
    public let paragraphCount: Int
    public let vocabularyDiversity: Double
    public let averageWordLength: Double
    public let readabilityScore: Double
    public let readingTime: Double
    public let speakingTime: Double
    public let detectedTone: DetectedTone
    public let writingScore: Int
    public let issueSummary: DocumentIssueSummary

    static func build(text: String, analysis: NLAnalysis?, issues: [WritingIssue]) -> DocumentMetrics {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.isEmpty
            ? 0
            : trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count

        let sentenceCount = analysis?.sentenceCount
            ?? max(1, text.components(separatedBy: .init(charactersIn: ".!?"))
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .count)

        let paragraphCount: Int = {
            guard !text.isEmpty else { return 0 }
            return text.components(separatedBy: "\n\n")
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .count
        }()

        let spelling = issues.filter { $0.type == .spelling }.count
        let grammar = issues.filter { $0.type == .grammar }.count
        let clarity = issues.filter { $0.type.category == .clarity }.count
        let engagement = issues.filter { $0.type.category == .engagement }.count
        let delivery = issues.filter { $0.type.category == .delivery }.count

        let issueSummary = DocumentIssueSummary(
            spelling: spelling,
            grammar: grammar,
            clarity: clarity,
            engagement: engagement,
            delivery: delivery,
            total: issues.count
        )

        let avgSentenceLength = analysis?.averageSentenceLength
            ?? (words > 0 ? Double(words) / Double(sentenceCount) : 0)

        let syllables = Double(analysis?.syllableCount ?? words)
        let wordCountDouble = Double(words)
        let sentenceCountDouble = Double(sentenceCount)
        let readability: Double = {
            guard wordCountDouble > 0, sentenceCountDouble > 0 else { return 100 }
            let score = 206.835 - 1.015 * (wordCountDouble / sentenceCountDouble) - 84.6 * (syllables / wordCountDouble)
            return max(0, min(100, score))
        }()

        let scale = max(1.0, Double(words) / 100.0)
        let correctnessPenalty = min(40.0, Double(spelling + grammar) * 4.0 / scale)
        let clarityPenalty = min(25.0, Double(clarity) * 3.0 / scale)
        let engagementPenalty = min(20.0, Double(engagement) * 2.0 / scale)
        let deliveryPenalty = min(15.0, Double(delivery) * 2.0 / scale)
        let score = words == 0
            ? 100
            : max(0, Int((100.0 - correctnessPenalty - clarityPenalty - engagementPenalty - deliveryPenalty).rounded()))

        return DocumentMetrics(
            wordCount: words,
            characterCount: text.count,
            sentenceCount: sentenceCount,
            averageSentenceLength: avgSentenceLength,
            paragraphCount: paragraphCount,
            vocabularyDiversity: analysis?.vocabularyDiversity ?? 0,
            averageWordLength: analysis?.averageWordLength ?? 0,
            readabilityScore: readability,
            readingTime: Double(words) / 250.0,
            speakingTime: Double(words) / 150.0,
            detectedTone: analysis?.detectedTone ?? .neutral,
            writingScore: score,
            issueSummary: issueSummary
        )
    }
}
