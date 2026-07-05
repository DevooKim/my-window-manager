import Foundation
import CoreGraphics

/// 스냅된 창의 "스냅 직전 크기"를 기억해, 드래그로 떼어낼 때 복원할 수 있게
/// 한다. 인메모리 전용 — 앱 재시작이나 창이 닫히면 자연히 사라진다(무해).
@MainActor
final class SnapRestoreStore {
    struct Entry: Equatable {
        let preSnapSize: CGSize   // 스냅 직전 창 크기
        let snappedFrame: CGRect  // 스냅으로 적용한 프레임(AX 좌표)
    }

    private var entries: [CGWindowID: Entry] = [:]

    func remember(windowID: CGWindowID, preSnapSize: CGSize, snappedFrame: CGRect) {
        entries[windowID] = Entry(preSnapSize: preSnapSize, snappedFrame: snappedFrame)
    }

    func entry(for windowID: CGWindowID) -> Entry? {
        entries[windowID]
    }

    func forget(_ windowID: CGWindowID) {
        entries[windowID] = nil
    }
}
