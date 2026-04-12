// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import Carbon.HIToolbox

/// Shared Accessibility API utilities. All functions are `nonisolated static` so they
/// can be called from background threads and detached tasks without actor hopping.
/// Each function encapsulates the repetitive "get focused element → guard type →
/// read attribute" pattern that was duplicated across 4+ call sites (#020).
public enum AXHelper {
    enum InspectionDecision: Equatable {
        case allow
        case denySecureInput
        case denySecureField
    }

    // MARK: - Focused Element

    /// Returns the currently focused `AXUIElement`, or `nil` on any failure.
    /// Skips elements belonging to this process (prevents WriteAssist reacting to itself).
    nonisolated static func focusedElement(skipSelf: Bool = false) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }

        let element = focusedRef as! AXUIElement // safe: type ID verified above

        if skipSelf {
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        }

        return element
    }

    // MARK: - Security Context

    nonisolated static func inspectionDecision(
        secureInputEnabled: Bool,
        role: String?,
        subrole: String?
    ) -> InspectionDecision {
        if secureInputEnabled {
            return .denySecureInput
        }
        if subrole == kAXSecureTextFieldSubrole as String {
            return .denySecureField
        }
        if let subrole, subrole.localizedCaseInsensitiveContains("secure")
            || subrole.localizedCaseInsensitiveContains("password") {
            return .denySecureField
        }
        if let role, role.localizedCaseInsensitiveContains("password") {
            return .denySecureField
        }
        return .allow
    }

    nonisolated static var isSecureInputEnabled: Bool {
        IsSecureEventInputEnabled()
    }

    nonisolated static func inspectionDecision(for element: AXUIElement) -> InspectionDecision {
        inspectionDecision(
            secureInputEnabled: isSecureInputEnabled,
            role: attributeString(kAXRoleAttribute as CFString, of: element),
            subrole: attributeString(kAXSubroleAttribute as CFString, of: element)
        )
    }

    nonisolated static func isSafeToInspect(_ element: AXUIElement) -> Bool {
        inspectionDecision(for: element) == .allow
    }

    // MARK: - String Value

    /// Reads `kAXValueAttribute` (full text) from an element, or `nil` on failure.
    nonisolated static func stringValue(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &ref
        ) == .success,
              let ref,
              let str = ref as? String
        else { return nil }
        return str
    }

    // MARK: - Selected Text

    /// Reads `kAXSelectedTextAttribute` from an element, or `nil` on failure.
    nonisolated static func selectedText(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &ref
        ) == .success,
              let ref,
              let str = ref as? String,
              !str.isEmpty
        else { return nil }
        return str
    }

    // MARK: - Selected Range

    /// Reads `kAXSelectedTextRangeAttribute` from an element as a raw `CFTypeRef`
    /// (an `AXValue` wrapping a `CFRange`). Returns `nil` on failure.
    nonisolated static func selectedRangeRef(of element: AXUIElement) -> CFTypeRef? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &ref
        ) == .success, let ref else { return nil }
        return ref
    }

    // MARK: - Caret Bounds

    /// Returns the screen `CGRect` (AX coordinate space, top-left origin) for the
    /// currently selected text in the focused element. Returns `nil` on any failure.
    public nonisolated static func selectedTextBounds(skipSelf: Bool = false) -> CGRect? {
        guard let element = focusedElement(skipSelf: skipSelf) else { return nil }
        guard let rangeRef = selectedRangeRef(of: element) else { return nil }
        return bounds(for: rangeRef, in: element)
    }

    /// Returns the screen `CGRect` (AX coordinate space, top-left origin) of
    /// the text caret in the currently focused element. Returns `nil` on any failure.
    nonisolated static func caretBounds() -> CGRect? {
        guard let element = focusedElement() else { return nil }
        guard let rangeRef = selectedRangeRef(of: element) else { return nil }
        return bounds(for: rangeRef, in: element)
    }

    /// Returns screen bounds for a given AX range ref in an element.
    nonisolated static func bounds(for rangeRef: CFTypeRef, in element: AXUIElement) -> CGRect? {
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef,
            &boundsRef
        ) == .success, let boundsRef else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    // MARK: - String for Range

    /// Reads a substring of the focused element's text using
    /// `kAXStringForRangeParameterizedAttribute`. More efficient than reading the
    /// full `kAXValueAttribute` when only a small window of text is needed (#029).
    nonisolated static func string(
        for rangeRef: CFTypeRef,
        in element: AXUIElement
    ) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeRef,
            &ref
        ) == .success,
              let ref,
              let str = ref as? String
        else { return nil }
        return str
    }

    // MARK: - Generic Attribute Reads

    private nonisolated static func attributeString(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let ref,
              let str = ref as? String else { return nil }
        return str
    }
}
