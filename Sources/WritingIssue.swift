// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation

enum IssueType: Sendable {
    case spelling
    case grammar
}

struct WritingIssue: Identifiable, Sendable {
    let id = UUID()
    let type: IssueType
    let range: NSRange
    let word: String
    let message: String
    let suggestions: [String]
    var isIgnored: Bool = false
}
