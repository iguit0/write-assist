// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit

/// Shared floating-panel positioning logic (#021).
/// Previously duplicated between `ErrorHUDPanel` and `SelectionSuggestionPanel`.
///
/// AX coordinates use a **top-left origin** (Y increases downward).
/// AppKit coordinates use a **bottom-left origin** (Y increases upward).
/// All conversions go through the primary screen height as a reference.
enum PanelPositioning {
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
        // Primary screen height is the coordinate-space reference.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900

        // Convert AX rect edges to AppKit Y coordinates.
        let caretTopAppKit    = primaryHeight - caretBounds.minY
        let caretBottomAppKit = primaryHeight - caretBounds.maxY
        let caretX            = caretBounds.origin.x

        // Find the screen containing the caret centre.
        let caretCenter = NSPoint(
            x: caretX + caretBounds.width / 2,
            y: (caretTopAppKit + caretBottomAppKit) / 2
        )
        let screen = NSScreen.screens.first { $0.frame.contains(caretCenter) }
        let visibleFrame = screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)

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
    /// Positions the panel near the top-right corner of the main screen.
    static func topRightFallback(panelSize: NSSize) -> NSPoint {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        return NSPoint(
            x: frame.maxX - panelSize.width - 16,
            y: frame.maxY - panelSize.height - 8
        )
    }
}
