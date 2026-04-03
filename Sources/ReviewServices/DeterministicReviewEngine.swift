// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

struct DeterministicReviewEngine: ReviewEngine {
    func analyze(
        document: ReviewDocument,
        preferences: ReviewPreferencesSnapshot
    ) async -> ReviewAnalysisSnapshot {
        let text = document.text
        let disabledRules = preferences.disabledRules

        // Step 1: Async spell + grammar check (already non-blocking via NSSpellChecker XPC)
        let spellIssues = await SpellCheckService.check(text: text)

        // Step 2: NL analysis — synchronous but uses NSLock internally.
        // Run off the main actor in a detached task to avoid blocking the UI.
        let analysis = await Task.detached(priority: .userInitiated) {
            NLAnalysisService.analyze(
                text,
                formality: preferences.formality,
                audience: preferences.audience
            )
        }.value

        // Step 3: Rule engine — nonisolated overload accepts snapshotted disabledRules,
        // so it never touches @MainActor PreferencesManager.
        let ruleIssues = RuleRegistry.runAll(text: text, analysis: analysis, disabledRules: disabledRules)

        // Step 4: Merge and deduplicate by stable issue id
        var seen = Set<String>()
        let allIssues = (spellIssues + ruleIssues).filter { seen.insert($0.id).inserted }

        // Step 5: Build document metrics
        let metrics = DocumentMetrics.build(text: text, analysis: analysis, issues: allIssues)

        // Step 6: Assemble snapshot — paragraphs is intentionally empty here;
        // ReviewGrouping (RW-202) is responsible for filling that field.
        return ReviewAnalysisSnapshot(
            documentID: document.id,
            documentRevision: document.revision,
            analyzedAt: Date(),
            analysis: analysis,
            issues: allIssues,
            metrics: metrics,
            paragraphs: []
        )
    }
}
