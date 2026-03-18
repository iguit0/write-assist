// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

@preconcurrency import AppKit
import CoreGraphics
import os

private let logger = Logger(subsystem: "com.writeassist", category: "CorrectionApplicator")

@MainActor
final class CorrectionApplicator {
    weak var inputMonitor: GlobalInputMonitor?
    var onCorrectionApplied: ((WritingIssue, String) -> Void)?

    private let writingStatsStore: WritingStatsStore

    private(set) var isCorrectionInFlight = false
    private(set) var lastCorrectionTime: ContinuousClock.Instant?
    private(set) var recentlyCorrectedIssueIDs: Set<String> = []

    private var lastCorrectionAXRange: CFRange?
    private var lastCorrectionOriginal: String?
    private var lastCorrectionReplacement: String?
    private var fallbackTask: Task<Void, Never>?

    private let hudCooldownAfterCorrection: Duration = .seconds(1.5)

    init(writingStatsStore: WritingStatsStore = .shared) {
        self.writingStatsStore = writingStatsStore
    }

    deinit {
        fallbackTask?.cancel()
    }

    func canShowHUD(now: ContinuousClock.Instant = .now) -> Bool {
        if isCorrectionInFlight {
            return false
        }
        if let lastCorrectionTime,
           now - lastCorrectionTime < hudCooldownAfterCorrection {
            return false
        }
        return true
    }

    func pruneRecentlyCorrected(keeping visibleIssueIDs: Set<String>) {
        recentlyCorrectedIssueIDs = recentlyCorrectedIssueIDs.filter { visibleIssueIDs.contains($0) }
    }

    func markInputMonitor(_ inputMonitor: GlobalInputMonitor?) {
        self.inputMonitor = inputMonitor
    }

    func apply(issue: WritingIssue, correction: String) {
        logger.info("apply: '\(issue.word, privacy: .sensitive)' → '\(correction, privacy: .sensitive)'")

        var didEmitCallback = false
        let emitCallback = { [weak self] in
            guard !didEmitCallback else { return }
            didEmitCallback = true
            self?.lastCorrectionOriginal = issue.word
            self?.lastCorrectionReplacement = correction
            self?.onCorrectionApplied?(issue, correction)
        }

        isCorrectionInFlight = true
        lastCorrectionTime = .now
        recentlyCorrectedIssueIDs.insert(issue.id)
        writingStatsStore.recordCorrection()

        inputMonitor?.replaceInBuffer(old: issue.word, new: correction)

        fallbackTask?.cancel()
        fallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            logger.warning("apply: AX timed out — fallback paste")
            let transaction = PasteboardTransaction.write(correction)
            Self.simulatePasteStatic()
            emitCallback()
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            transaction.restoreIfUnchanged()
            self?.isCorrectionInFlight = false
        }

        let word = issue.word
        let axTask = Task.detached(priority: .userInitiated) {
            Self.injectCorrectionViaAXBackgroundResult(word: word, correction: correction)
        }

        Task { @MainActor [weak self] in
            let axResult = await axTask.value
            self?.lastCorrectionAXRange = axResult.success ? axResult.replacementRange : nil
            self?.fallbackTask?.cancel()

            if !axResult.success {
                logger.warning("apply: AX failed — fallback paste")
                let transaction = PasteboardTransaction.write(correction)
                Self.simulatePasteStatic()
                emitCallback()
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                transaction.restoreIfUnchanged()
            } else {
                emitCallback()
            }

            self?.isCorrectionInFlight = false
        }
    }

    func undo(original: String, correction: String) {
        logger.info("undo: '\(correction, privacy: .sensitive)' → '\(original, privacy: .sensitive)'")

        isCorrectionInFlight = true
        lastCorrectionTime = .now

        inputMonitor?.replaceInBuffer(old: correction, new: original)

        let rangeOverride: CFRange? = (lastCorrectionOriginal == original
            && lastCorrectionReplacement == correction) ? lastCorrectionAXRange : nil
        lastCorrectionAXRange = nil

        fallbackTask?.cancel()
        fallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let transaction = PasteboardTransaction.write(original)
            Self.simulatePasteStatic()
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            transaction.restoreIfUnchanged()
            self?.isCorrectionInFlight = false
        }

        let axTask = Task.detached(priority: .userInitiated) {
            Self.injectCorrectionViaAXBackground(word: correction, correction: original, rangeOverride: rangeOverride)
        }

        Task { @MainActor [weak self] in
            let axSucceeded = await axTask.value
            self?.fallbackTask?.cancel()

            if !axSucceeded {
                let transaction = PasteboardTransaction.write(original)
                Self.simulatePasteStatic()
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                transaction.restoreIfUnchanged()
            }

            self?.isCorrectionInFlight = false
        }
    }

    func replaceSelection(replacement: String) {
        logger.info("replaceSelection: length=\(replacement.count)")

        isCorrectionInFlight = true
        lastCorrectionTime = .now

        fallbackTask?.cancel()
        fallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let transaction = PasteboardTransaction.write(replacement)
            Self.simulatePasteStatic()
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            transaction.restoreIfUnchanged()
            self?.isCorrectionInFlight = false
        }

        let axTask = Task.detached(priority: .userInitiated) {
            Self.injectSelectedTextViaAXBackground(replacement: replacement)
        }

        Task { @MainActor [weak self] in
            let axSucceeded = await axTask.value
            self?.fallbackTask?.cancel()

            if !axSucceeded {
                let transaction = PasteboardTransaction.write(replacement)
                Self.simulatePasteStatic()
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                transaction.restoreIfUnchanged()
            }

            self?.isCorrectionInFlight = false
        }
    }

    private struct AXCorrectionResult {
        let success: Bool
        let replacementRange: CFRange?
    }

    private nonisolated static func injectCorrectionViaAXBackgroundResult(
        word: String,
        correction: String
    ) -> AXCorrectionResult {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success, let focusedValue else {
            return AXCorrectionResult(success: false, replacementRange: nil)
        }

        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return AXCorrectionResult(success: false, replacementRange: nil)
        }
        let element = focusedValue as! AXUIElement

        var textValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &textValue
        ) == .success,
              let textValue,
              let fullText = textValue as? String,
              let wordRange = fullText.range(of: word, options: .backwards) else {
            return AXCorrectionResult(success: false, replacementRange: nil)
        }

        let nsRange = NSRange(wordRange, in: fullText)
        var cfRange = CFRange(location: nsRange.location, length: nsRange.length)
        guard let axRange = AXValueCreate(.cfRange, &cfRange) else {
            return AXCorrectionResult(success: false, replacementRange: nil)
        }

        let setRangeResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            axRange
        )
        guard setRangeResult == .success else {
            return AXCorrectionResult(success: false, replacementRange: nil)
        }

        let setTextResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            correction as CFString
        )
        let replacementLength = (correction as NSString).length
        let replacementRange = CFRange(location: nsRange.location, length: replacementLength)

        return AXCorrectionResult(
            success: setTextResult == .success,
            replacementRange: replacementRange
        )
    }

    private nonisolated static func injectCorrectionViaAXBackground(
        word: String,
        correction: String,
        rangeOverride: CFRange?
    ) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success, let focusedValue else {
            return false
        }

        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return false
        }
        let element = focusedValue as! AXUIElement

        var textValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &textValue
        ) == .success,
              let textValue,
              let fullText = textValue as? String else {
            return false
        }

        let nsRange: NSRange
        if let rangeOverride,
           rangeOverride.location >= 0,
           rangeOverride.length >= 0,
           rangeOverride.location + rangeOverride.length <= (fullText as NSString).length {
            nsRange = NSRange(location: rangeOverride.location, length: rangeOverride.length)
        } else {
            guard let wordRange = fullText.range(of: word, options: .backwards) else { return false }
            nsRange = NSRange(wordRange, in: fullText)
        }

        var cfRange = CFRange(location: nsRange.location, length: nsRange.length)
        guard let axRange = AXValueCreate(.cfRange, &cfRange) else { return false }

        let setRangeResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            axRange
        )
        guard setRangeResult == .success else {
            return false
        }

        let setTextResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            correction as CFString
        )
        return setTextResult == .success
    }

    private static func simulatePasteStatic() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cgAnnotatedSessionEventTap)
        vUp?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private nonisolated static func injectSelectedTextViaAXBackground(replacement: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return false
        }

        let element = focusedRef as! AXUIElement
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            replacement as CFString
        )

        return result == .success
    }
}
