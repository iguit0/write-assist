// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import SwiftUI

/// A SwiftUI-compatible text view that renders captured text with inline
/// error highlighting: dotted red underlines for spelling errors and dotted
/// orange underlines for grammar errors, matching the style used by macOS's
/// built-in spell checker.
struct HighlightedTextView: NSViewRepresentable {
    let text: String
    let issues: [WritingIssue]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.textColor = NSColor.labelColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(buildAttributedString())
    }

    private func buildAttributedString() -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ]
        let result = NSMutableAttributedString(string: text, attributes: base)
        let nsString = text as NSString

        for issue in issues where !issue.isIgnored {
            // Guard against stale ranges when the buffer changes mid-check
            guard issue.range.location != NSNotFound,
                  issue.range.location + issue.range.length <= nsString.length else {
                continue
            }
            let color: NSColor = issue.type == .spelling ? .systemRed : .systemOrange
            result.addAttributes([
                .underlineStyle: NSUnderlineStyle.patternDot.rawValue
                    | NSUnderlineStyle.single.rawValue,
                .underlineColor: color,
                .backgroundColor: color.withAlphaComponent(0.08)
            ], range: issue.range)
        }
        return result
    }
}
