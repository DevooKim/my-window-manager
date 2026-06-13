import ApplicationServices
import AppKit

enum WindowController {
    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &win
        ) == .success, let win else { return nil }
        return (win as! AXUIElement)
    }

    static func firstWindow(of bundleId: String) -> AXUIElement? {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleId).first
        else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref)
        if let arr = ref as? [AXUIElement] {
            for w in arr {
                if let mini = boolAttr(w, kAXMinimizedAttribute), mini { continue }
                return w
            }
            return arr.first
        }
        return nil
    }

    static func setFrame(_ window: AXUIElement, frame: CGRect) {
        unsetFullscreen(window)
        var pos = frame.origin
        var size = frame.size
        if let p = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
        }
        if let s = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s)
        }
        if let p = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
        }
    }

    static func getFrame(_ window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        guard let posRef, let sizeRef else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    static func unsetFullscreen(_ window: AXUIElement) {
        if let isFull = boolAttr(window, "AXFullScreen"), isFull {
            AXUIElementSetAttributeValue(
                window, "AXFullScreen" as CFString, false as CFTypeRef
            )
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    private static func boolAttr(_ element: AXUIElement, _ attr: String) -> Bool? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attr as CFString, &ref)
        return ref as? Bool
    }
}
