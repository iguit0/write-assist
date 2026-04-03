// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import SwiftUI

// MARK: - ReviewEditorBridge

/// An editable NSTextView bridge for the Review Workbench editor pane.
/// Models the same NSScrollView / Coordinator pattern as HighlightedTextView
/// but exposes an editable text field and reports both text and selection changes.
struct ReviewEditorBridge: NSViewRepresentable {
    let text: String
    let issues: [WritingIssue]
    let highlightedRange: NSRange?
    let onTextChanged: (String) -> Void
    let onSelectionChanged: (NSRange?) -> Void

    // MARK: makeNSView

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor.labelColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        textView.delegate = context.coordinator
        return scrollView
    }

    // MARK: updateNSView

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Refresh coordinator callbacks so they always hold the latest closures.
        // Without this, callbacks capture a stale reference after re-renders.
        context.coordinator.onTextChanged = onTextChanged
        context.coordinator.onSelectionChanged = onSelectionChanged

        let issueIDs = issues.map(\.id)
        let textOrIssuesChanged = text != context.coordinator.lastText
            || issueIDs != context.coordinator.lastIssueIDs
        if textOrIssuesChanged {
            context.coordinator.lastText = text
            context.coordinator.lastIssueIDs = issueIDs
            textView.textStorage?.setAttributedString(buildAttributedString())
        }

        // Scroll the highlighted range into view whenever it changes.
        if let range = highlightedRange, range != context.coordinator.lastHighlightedRange {
            context.coordinator.lastHighlightedRange = range
            textView.scrollRangeToVisible(range)
        }
    }

    // MARK: makeCoordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChanged: onTextChanged, onSelectionChanged: onSelectionChanged)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onTextChanged: (String) -> Void
        var onSelectionChanged: (NSRange?) -> Void
        var lastText: String = ""
        var lastIssueIDs: [String] = []
        var lastHighlightedRange: NSRange?

        init(
            onTextChanged: @escaping (String) -> Void,
            onSelectionChanged: @escaping (NSRange?) -> Void
        ) {
            self.onTextChanged = onTextChanged
            self.onSelectionChanged = onSelectionChanged
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            // Keep lastText in sync so updateNSView skips a redundant rebuild.
            lastText = newText
            onTextChanged(newText)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            onSelectionChanged(range.length > 0 ? range : nil)
        }
    }

    // MARK: - Attributed string builder

    private func buildAttributedString() -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor
        ]
        let result = NSMutableAttributedString(string: text, attributes: base)
        let nsString = text as NSString

        for issue in issues {
            // Guard against stale ranges when the buffer changes mid-check.
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

// MARK: - ReviewEditorView

/// A thin SwiftUI wrapper that connects `ReviewEditorBridge` to `ReviewSessionStore`.
public struct ReviewEditorView: View {
    let store: ReviewSessionStore

    public init(store: ReviewSessionStore) {
        self.store = store
    }

    public var body: some View {
        ReviewEditorBridge(
            text: store.document.text,
            issues: currentIssues,
            highlightedRange: store.selectedEditorRange,
            onTextChanged: { [store] newText in
                store.replaceText(newText)
            },
            onSelectionChanged: { [store] range in
                store.selectedEditorRange = range
            }
        )
    }

    private var currentIssues: [WritingIssue] {
        if case .ready(let snapshot) = store.analysisState {
            return snapshot.issues
        }
        return []
    }
}
