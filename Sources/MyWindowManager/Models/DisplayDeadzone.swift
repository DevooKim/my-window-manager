import Foundation
import CoreGraphics

/// Per-display "deadzone" — pixel insets carved off each edge of a display's
/// usable area before any window is placed. Applies to both resize presets and
/// layouts (anything that resolves a frame against `ScreenHelper.placementArea`).
///
/// `displayID` is the stable `CGDisplayCreateUUIDFromDisplayID` string so the
/// deadzone follows the physical monitor across reboots and rearrangement.
/// `displayName` is only the last-seen `localizedName`, kept for the UI.
struct DisplayDeadzone: Codable, Hashable, Identifiable {
    var displayID: String
    var displayName: String
    var top: CGFloat = 0
    var bottom: CGFloat = 0
    var left: CGFloat = 0
    var right: CGFloat = 0

    var id: String { displayID }

    /// True when every edge inset is zero — nothing to carve off.
    var isZero: Bool {
        top == 0 && bottom == 0 && left == 0 && right == 0
    }

    /// Inset `area` (in top-left AX coordinates) by this deadzone. Edges are
    /// clamped so the result never inverts on tiny displays.
    func inset(_ area: CGRect) -> CGRect {
        let l = max(0, left), r = max(0, right)
        let t = max(0, top), b = max(0, bottom)
        var rect = area
        rect.origin.x += l
        rect.origin.y += t   // top-left origin: +y moves down
        rect.size.width = max(1, area.width - l - r)
        rect.size.height = max(1, area.height - t - b)
        return rect
    }
}
