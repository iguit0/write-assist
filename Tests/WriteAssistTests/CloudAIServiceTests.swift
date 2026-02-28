// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Testing
import Foundation
@testable import WriteAssistCore

// MARK: - CloudAIService.parseSpellCheckResponse

@Suite("CloudAIService.parseSpellCheckResponse")
struct ParseSpellCheckResponseTests {
    private let sampleText = "I recieved your mesage yesterday"

    @Test("parses valid JSON response")
    func parsesValidJSON() {
        let response = """
        [
          {"word": "recieved", "offset": 2, "corrections": ["received"]},
          {"word": "mesage", "offset": 17, "corrections": ["message"]}
        ]
        """
        let issues = CloudAIService.parseSpellCheckResponse(response, text: sampleText)
        #expect(issues.count == 2)
        #expect(issues[0].word == "recieved")
        #expect(issues[0].suggestions == ["received"])
        #expect(issues[0].ruleID == "spelling")
        #expect(issues[1].word == "mesage")
    }

    @Test("strips markdown code fences")
    func stripsMarkdownCodeFences() {
        let response = """
        ```json
        [{"word": "recieved", "offset": 2, "corrections": ["received"]}]
        ```
        """
        let issues = CloudAIService.parseSpellCheckResponse(response, text: sampleText)
        #expect(issues.count == 1)
        #expect(issues[0].word == "recieved")
    }

    @Test("repairs truncated JSON array")
    func repairsTruncatedJSON() {
        // Model cut off before the closing bracket
        let truncated = """
        [{"word": "recieved", "offset": 2, "corrections": ["received"]}
        """
        let issues = CloudAIService.parseSpellCheckResponse(truncated, text: sampleText)
        #expect(issues.count == 1)
    }

    @Test("returns empty for invalid JSON")
    func returnsEmptyForInvalidJSON() {
        let issues = CloudAIService.parseSpellCheckResponse("not json at all", text: sampleText)
        #expect(issues.isEmpty)
    }

    @Test("returns empty for empty response")
    func returnsEmptyForEmptyResponse() {
        let issues = CloudAIService.parseSpellCheckResponse("", text: sampleText)
        #expect(issues.isEmpty)
    }

    @Test("handles empty corrections array")
    func handlesEmptyCorrections() {
        let response = """
        [{"word": "recieved", "offset": 2, "corrections": []}]
        """
        let issues = CloudAIService.parseSpellCheckResponse(response, text: sampleText)
        // word with no corrections is still a valid issue
        #expect(issues.count == 1)
        #expect(issues[0].suggestions.isEmpty)
    }

    @Test("skips entries where corrections echo the word (false positives)")
    func skipsCorrectionsEchoingWord() {
        let response = """
        [{"word": "recieved", "offset": 2, "corrections": ["recieved"]}]
        """
        let issues = CloudAIService.parseSpellCheckResponse(response, text: sampleText)
        // The only suggestion IS the misspelled word — filtered out → entry skipped
        #expect(issues.isEmpty)
    }

    @Test("falls back to text search when offset is wrong")
    func fallsBackToTextSearchOnBadOffset() {
        // Offset 999 is out of bounds, should fall back to case-insensitive search
        let response = """
        [{"word": "recieved", "offset": 999, "corrections": ["received"]}]
        """
        let issues = CloudAIService.parseSpellCheckResponse(response, text: sampleText)
        #expect(issues.count == 1)
        #expect(issues[0].word == "recieved")
    }

    @Test("skips entries missing the word field")
    func skipsEntriesMissingWord() {
        let response = """
        [{"offset": 2, "corrections": ["received"]}]
        """
        let issues = CloudAIService.parseSpellCheckResponse(response, text: sampleText)
        #expect(issues.isEmpty)
    }
}

// MARK: - CloudAIPinning

@Suite("CloudAIPinning")
struct CloudAIPinningTests {
    @Test("sha256Base64 matches expected digest")
    func sha256Base64MatchesExpectedDigest() {
        let data = Data("pin".utf8)
        #expect(CloudAIPinning.sha256Base64(data) == "ZPRqdSahhtI0ZVJFOuR4ylEkRnT1shuhUL1IOzn3yBI=")
    }
}
