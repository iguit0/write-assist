// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit

/// Shared floating-panel positioning logic (#021).
/// Previously duplicated between `ErrorHUDPanel` and `SelectionSuggestionPanel`.
///
/// AX coordinates use a **top-left origin** (Y increases downward).
/// AppKit coordinates use a **bottom-left origin** (Y increases upward).
/// All conversions use the menu-bar screen (always at AppKit origin) as the
/// coordinate-space reference.
enum PanelPositioning {

    private static let fallbackFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)

    // MARK: - Caret-Anchored Origin

    /// Returns the AppKit window origin for a floating panel anchored near the text caret.
    ///
    /// The panel appears **below** the caret with a small gap. If placing it below would
    /// push it off the visible screen area, the panel flips **above** the caret instead.
    /// The X position is clamped to keep the panel fully within the screen.
    ///
    /// - Parameters:
    ///   - caretBounds: Caret rectangle in AX screen coordinates (top-left origin).
    ///   - panelSize:   Measured size of the panel to position.
    ///   - gap:         Vertical gap between caret and panel edge. Default: 4 pt.
    /// - Returns: The AppKit window origin (bottom-left corner of the panel).
    static func origin(caretBounds: CGRect, panelSize: NSSize, gap: CGFloat = 4) -> NSPoint {
        // The menu-bar screen is the AX coordinate-space reference.
        // `NSScreen.screens.first` is the reliable choice here: macOS guarantees
        // the menu-bar display is first. We deliberately avoid `NSScreen.main`,
        // which tracks the key-window screen and is unreliable (can be nil) in
        // `.accessory`-policy apps that have no key window.
        let referenceScreen = NSScreen.screens.first
        let referenceFrame  = referenceScreen?.frame ?? fallbackFrame

        // Find which physical screen the caret is on by converting its mid-point
        // to AX space and checking each screen's AX-space bounds.
        // The previous approach converted the caret to AppKit Y first, then
        // called `screen.frame.contains(caretCenter)` — a mixed-coordinate check
        // that silently fails when the converted point lies outside all frames,
        // collapsing the fallback to `NSScreen.main` and clamping to bottom-left.
        let caretAXMid  = CGPoint(x: caretBounds.midX, y: caretBounds.midY)
        let targetScreen = screenContainingAXPoint(caretAXMid, referenceFrame: referenceFrame)

        // Fall back to the reference screen's visible frame, never `NSScreen.main`.
        let visibleFrame = targetScreen?.visibleFrame
            ?? referenceScreen?.visibleFrame
            ?? fallbackFrame

        // Convert AX rect edges to AppKit Y coordinates.
        let caretTopAppKit    = referenceFrame.maxY - caretBounds.minY
        let caretBottomAppKit = referenceFrame.maxY - caretBounds.maxY
        let caretX            = caretBounds.origin.x

        // Try placing below the caret; flip above if it would overflow.
        var y = caretBottomAppKit - gap - panelSize.height
        if y < visibleFrame.minY {
            y = caretTopAppKit + gap
        }

        // Align X with the caret left edge, clamped to screen.
        var x = caretX
        x = max(visibleFrame.minX + 8, min(x, visibleFrame.maxX - panelSize.width - 8))
        // Final Y clamp.
        y = max(visibleFrame.minY, min(y, visibleFrame.maxY - panelSize.height))

        return NSPoint(x: x, y: y)
    }

    // MARK: - Top-Right Fallback

    /// Fallback origin for when the caret position cannot be determined via AX.
    /// Positions the panel near the top-right corner of the primary screen.
    static func topRightFallback(panelSize: NSSize) -> NSPoint {
        let frame = NSScreen.screens.first?.visibleFrame ?? fallbackFrame
        return NSPoint(
            x: frame.maxX - panelSize.width - 16,
            y: frame.maxY - panelSize.height - 8
        )
    }

    // MARK: - Private Helpers

    /// Returns the screen that contains `point` expressed in AX coordinate space.
    ///
    /// AX coordinates are global, with origin at the top-left of the primary screen.
    /// Each screen's AppKit frame is converted to AX space before the containment check,
    /// avoiding the mixed-coordinate-space bug in the previous implementation.
    private static func screenContainingAXPoint(
        _ point: CGPoint,
        referenceFrame: CGRect
    ) -> NSScreen? {
        NSScreen.screens.first { screen in
            // Convert the screen's AppKit frame to AX coordinate space:
            //   AX.x = AppKit.x       (horizontal axis is identical)
            //   AX.y = referenceFrame.maxY − AppKit.frame.maxY
            let axFrame = CGRect(
                x: screen.frame.minX,
                y: referenceFrame.maxY - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
            return axFrame.contains(point)
        }
    }
}
