// WriteAssist — macOS menu bar writing assistant
// Copyright © 2024 Igor Alves. All rights reserved.

import Foundation

protocol ReviewEngine: Sendable {
    func analyze(
        document: ReviewDocument,
        preferences: ReviewPreferencesSnapshot
    ) async -> ReviewAnalysisSnapshot
}

struct PlaceholderReviewEngine: ReviewEngine {
    func analyze(
        document: ReviewDocument,
        preferences: ReviewPreferencesSnapshot
    ) async -> ReviewAnalysisSnapshot {
        let emptyAnalysis = NLAnalysis(
            sentenceRanges: [],
            words: [],
            wordPOSTags: [],
            syllableCount: 0,
            wordFrequency: [:],
            detectedTone: .neutral,
            formalityLevel: preferences.formality,
            audienceLevel: preferences.audience
        )
        let emptyMetrics = DocumentMetrics.build(text: "", analysis: nil, issues: [])
        return ReviewAnalysisSnapshot(
            documentID: document.id,
            documentRevision: document.revision,
            analyzedAt: Date(),
            analysis: emptyAnalysis,
            issues: [],
            metrics: emptyMetrics,
            paragraphs: []
        )
    }
}
