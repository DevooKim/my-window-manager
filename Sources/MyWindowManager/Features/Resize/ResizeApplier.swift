import AppKit
import ApplicationServices

enum ResizeApplier {
    @discardableResult
    static func apply(_ preset: ResizePreset) -> Bool {
        guard let window = WindowController.focusedWindow() else {
            return false
        }
        return apply(preset, to: window)
    }

    @discardableResult
    static func apply(_ preset: ResizePreset, to window: AXUIElement) -> Bool {
        guard let screen = ScreenHelper.screen(containing: window) else {
            return false
        }
        let area = ScreenHelper.placementArea(of: screen)
        let frame = preset.frame.resolve(in: area)
        WindowController.setFrame(window, frame: frame)
        return true
    }

    static func previewFrame(_ preset: ResizePreset, on screen: NSScreen) -> CGRect {
        preset.frame.resolve(in: ScreenHelper.placementArea(of: screen))
    }
}
