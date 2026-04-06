// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import Foundation

/// One-shot selection import using the Accessibility API.
///
/// Reads the currently selected text from the focused application exactly once.
/// Does not start background polling, monitoring, or any persistent observation.
public struct SelectionImportService: SelectionImporting {
    public init() {}

    public func importCurrentSelection() async throws -> ImportedSelection {
        // Check AX permission
        guard AXIsProcessTrusted() else {
            throw SelectionImportError.accessibilityDenied
        }

        // Check secure input (password fields, login screens)
        guard !AXHelper.isSecureInputEnabled else {
            throw SelectionImportError.secureContext
        }

        // Get focused element from the frontmost app, skipping WriteAssist itself
        guard let element = AXHelper.focusedElement(skipSelf: true) else {
            throw SelectionImportError.noFocusedElement
        }

        // Guard against secure contexts (password fields, secure subrolees)
        let decision = AXHelper.inspectionDecision(for: element)
        guard decision == .allow else {
            throw SelectionImportError.secureContext
        }

        // Read selected text — empty or nil means nothing is selected
        guard let text = AXHelper.selectedText(of: element), !text.isEmpty else {
            throw SelectionImportError.noSelection
        }

        // Resolve source-app metadata from the element's PID
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let metadata = await resolveMetadata(pid: pid)

        return ImportedSelection(text: text, metadata: metadata)
    }

    // MARK: - Helpers

    @MainActor
    private func resolveMetadata(pid: pid_t) -> ImportedSelectionMetadata {
        let app = NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier == pid
        }
        return ImportedSelectionMetadata(
            appName: app?.localizedName,
            bundleIdentifier: app?.bundleIdentifier,
            importedAt: Date()
        )
    }
}
