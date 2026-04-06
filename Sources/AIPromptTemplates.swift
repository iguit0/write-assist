// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

enum AIRewriteStyle: String, CaseIterable, Sendable {
    case grammarFix = "Fix Grammar"
    case clearer = "Make clearer"
    case concise = "Make more concise"
    case formal = "Make more formal"
    case friendly = "Make friendlier"
    case rephrase = "Rephrase"

    var instruction: String {
        switch self {
        case .grammarFix:
            return "Fix all grammar, spelling, punctuation, and sentence-structure errors. Preserve the original wording, style, and meaning as closely as possible — only correct what is grammatically wrong."
        case .clearer:
            return "Rewrite this text to be clearer and easier to understand. Preserve the original meaning, tone, and approximate length."
        case .concise:
            return "Rewrite this text to be shorter. Cut filler words, redundant phrases, and unnecessary qualifiers. Aim for 30-50% fewer words while preserving meaning."
        case .formal:
            return "Rewrite this text in a professional, formal tone. Replace colloquialisms with standard language. Keep the same meaning and structure."
        case .friendly:
            return "Rewrite this text in a warmer, more conversational tone. Keep the same meaning and structure."
        case .rephrase:
            return "Rephrase this text in a fresh, different way while keeping the same meaning."
        }
    }
}

enum AIPromptTemplates {
    static func rewritePrompt(text: String, style: AIRewriteStyle, formality: FormalityLevel, audience: AudienceLevel) -> (system: String, user: String) {
        let system = """
        You are a writing editor. Your sole job is to rewrite text.
        STRICT OUTPUT RULES — violating any rule is a failure:
        1. Output ONLY the rewritten text. Nothing else.
        2. Do NOT include any preamble, e.g. "Here's a rewritten version:", "Sure!", "I've rewritten this as:", etc.
        3. Do NOT add explanations, commentary, or quotation marks around the result.
        4. Keep the output at approximately the same length as the input — do not expand it.
        5. Match formality to "\(formality.rawValue)" register, audience to "\(audience.rawValue)".
        6. Preserve any line breaks, bullet points, or numbered lists.
        If the input is a single sentence, output a single sentence.
        """
        let user = "\(style.instruction)\n\nText to rewrite:\n\(text)"
        return (system, user)
    }

    static func toneAnalysisPrompt(text: String) -> (system: String, user: String) {
        let system = """
        Analyze the tone of the given text. Respond with ONLY a JSON object, no other text. \
        Schema: {"tone": string, "confidence": number, "phrases": [string]} \
        tone: one of "Confident", "Tentative", "Formal", "Casual", "Friendly", "Neutral". \
        confidence: a decimal between 0.0 and 1.0 indicating how strongly the tone is present. \
        phrases: 1-3 exact quotes from the text that most strongly signal the detected tone.
        """
        let user = text
        return (system, user)
    }

    static func smartSuggestionPrompt(text: String, issueMessage: String) -> (system: String, user: String) {
        let system = """
        You fix writing issues. Given text and a specific issue, provide 1-3 corrected versions. \
        Rules: \
        1. Fix ONLY the stated issue — do not rephrase or restructure beyond what is needed. \
        2. Each suggestion must be a complete replacement for the original text, similar in length. \
        3. Output each suggestion on its own line. No numbering, no bullets, no explanations.
        """
        let user = "Issue: \(issueMessage)\n\nText:\n\(text)"
        return (system, user)
    }

    static func chatAssistantPrompt() -> String {
        """
        You are WriteAssist, a writing assistant in a macOS menu bar popover. \
        Help with composing, editing, summarizing, and brainstorming text. \
        Keep responses short — this is a small window, not a full chat app. \
        When asked to write or rewrite, output the result directly with no preamble. \
        Use markdown formatting only when the user asks for lists or structured output.
        """
    }

    static func spellCheckPrompt(text: String) -> (system: String, user: String) {
        let system = """
        Find spelling errors in the user's text. Report ONLY misspelled words — \
        ignore grammar, punctuation, style, capitalization, and word choice. \
        Skip proper nouns, acronyms, URLs, email addresses, file paths, and technical terms. \
        For each error, report the exact misspelled word, its 0-based character offset, and up to 3 corrections. \
        Respond with a JSON array and nothing else. No markdown, no prose. \
        Empty text or no errors → []\n\
        Example: [{"word":"teh","offset":4,"corrections":["the","tea"]}]
        """
        return (system, text)
    }
}
