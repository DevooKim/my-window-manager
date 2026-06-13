import AppKit
import ApplicationServices

enum ScreenHelper {
    /// Active per-display deadzones, keyed by stable display ID. Kept in sync by
    /// `ConfigStore` so the appliers (which call `placementArea`) don't need a
    /// reference to the store. Read on the main thread.
    static var deadzonesByDisplayID: [String: DisplayDeadzone] = [:]

    static func axVisibleFrame(of screen: NSScreen) -> CGRect {
        guard let primary = NSScreen.screens.first else { return screen.visibleFrame }
        let f = screen.visibleFrame
        return CGRect(
            x: f.minX,
            y: primary.frame.maxY - f.maxY,
            width: f.width,
            height: f.height
        )
    }

    static func axFullFrame(of screen: NSScreen) -> CGRect {
        guard let primary = NSScreen.screens.first else { return screen.frame }
        let f = screen.frame
        return CGRect(
            x: f.minX,
            y: primary.frame.maxY - f.maxY,
            width: f.width,
            height: f.height
        )
    }

    /// The usable area windows are placed into — `axVisibleFrame` with this
    /// display's deadzone insets applied. Use this from the appliers; use the
    /// raw `axVisibleFrame` for hit-testing (`screen(containing:)`) so windows
    /// sitting inside a deadzone still resolve to their screen.
    static func placementArea(of screen: NSScreen) -> CGRect {
        let area = axVisibleFrame(of: screen)
        guard let id = stableID(of: screen),
              let dz = deadzonesByDisplayID[id], !dz.isZero else { return area }
        return dz.inset(area)
    }

    static func screen(containing window: AXUIElement) -> NSScreen? {
        guard let frame = WindowController.getFrame(window) else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { axVisibleFrame(of: $0).contains(center) }
            ?? NSScreen.main
    }

    static func resolve(_ matcher: DisplayMatcher) -> NSScreen? {
        switch matcher {
        case .primary:
            return NSScreen.screens.first
        case .index(let i):
            return i < NSScreen.screens.count ? NSScreen.screens[i] : NSScreen.screens.first
        case .name(let name):
            return NSScreen.screens.first { $0.localizedName == name }
                ?? NSScreen.screens.first
        }
    }

    // MARK: - Stable display identity

    /// `CGDirectDisplayID` for an `NSScreen`, read from its device description.
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    /// Stable identifier for a physical display — the UUID derived from its
    /// `CGDirectDisplayID`. Survives reboots and rearrangement, unlike the
    /// raw display ID or the array index.
    static func stableID(of screen: NSScreen) -> String? {
        guard let did = displayID(of: screen),
              let uuid = CGDisplayCreateUUIDFromDisplayID(did)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
