import Testing
import CoreGraphics
@testable import MyWindowManager

@MainActor
struct SnapRestoreStoreTests {
    @Test func rememberAndForget() {
        let store = SnapRestoreStore()
        let id: CGWindowID = 42
        #expect(store.entry(for: id) == nil)

        store.remember(windowID: id,
                       preSnapSize: CGSize(width: 800, height: 600),
                       snappedFrame: CGRect(x: 0, y: 25, width: 960, height: 1055))
        let entry = store.entry(for: id)
        #expect(entry?.preSnapSize == CGSize(width: 800, height: 600))
        #expect(entry?.snappedFrame == CGRect(x: 0, y: 25, width: 960, height: 1055))

        store.forget(id)
        #expect(store.entry(for: id) == nil)
    }

    @Test func reSnapOverwrites() {
        let store = SnapRestoreStore()
        store.remember(windowID: 1, preSnapSize: CGSize(width: 100, height: 100),
                       snappedFrame: .zero)
        store.remember(windowID: 1, preSnapSize: CGSize(width: 200, height: 200),
                       snappedFrame: .zero)
        #expect(store.entry(for: 1)?.preSnapSize == CGSize(width: 200, height: 200))
    }
}
