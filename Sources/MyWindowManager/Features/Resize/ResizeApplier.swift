import AppKit
import ApplicationServices

enum ResizeApplier {
    @discardableResult
    static func apply(_ preset: ResizePreset) -> Bool {
        guard let win = WindowController.focusedWindow(),
              let screen = ScreenHelper.screen(containing: win) else {
            return false
        }
        let area = ScreenHelper.axVisibleFrame(of: screen)
        let frame = preset.frame.resolve(in: area)
        WindowController.setFrame(win, frame: frame)
        return true
    }

    static func previewFrame(_ preset: ResizePreset, on screen: NSScreen) -> CGRect {
        preset.frame.resolve(in: ScreenHelper.axVisibleFrame(of: screen))
    }
}
