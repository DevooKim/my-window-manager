import AppKit
import ApplicationServices

enum ScreenHelper {
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
}
