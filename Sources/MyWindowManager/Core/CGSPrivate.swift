import Foundation
import CoreGraphics
import ApplicationServices

/// 비공개 CGS/SkyLight 심볼을 런타임 dlsym으로 로드한다. OS 업데이트로 심볼이
/// 사라지면 각 프로퍼티가 nil이 되고, 호출부는 조용히 no-op 처리한다.
/// (스페이스 이동에 공개 API가 없어 불가피하게 사용 — design 문서 참조.)
enum CGSPrivate {
    typealias ConnID = UInt32   // CGSConnectionID
    typealias SpaceID = UInt64  // CGSSpaceID

    // SkyLight.framework 핸들 (CoreGraphics가 재노출). 전역에서 dlsym.
    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static func sym(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(handle, name) ?? dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) // RTLD_DEFAULT
    }

    // CGSConnectionID CGSMainConnectionID(void)
    typealias MainConnectionFn = @convention(c) () -> ConnID
    static let mainConnectionID: MainConnectionFn? =
        sym("CGSMainConnectionID").map { unsafeBitCast($0, to: MainConnectionFn.self) }

    // CGSSpaceID CGSGetActiveSpace(CGSConnectionID)
    typealias GetActiveSpaceFn = @convention(c) (ConnID) -> SpaceID
    static let getActiveSpace: GetActiveSpaceFn? =
        sym("CGSGetActiveSpace").map { unsafeBitCast($0, to: GetActiveSpaceFn.self) }

    // CFArrayRef CGSCopySpaces(CGSConnectionID, int mask)
    // mask 7 = all spaces (current + others) for the connection.
    typealias CopySpacesFn = @convention(c) (ConnID, Int32) -> Unmanaged<CFArray>?
    static let copySpaces: CopySpacesFn? =
        sym("CGSCopySpaces").map { unsafeBitCast($0, to: CopySpacesFn.self) }

    // void CGSMoveWindowsToManagedSpace(CGSConnectionID, CFArrayRef windows, CGSSpaceID)
    typealias MoveWindowsFn = @convention(c) (ConnID, CFArray, SpaceID) -> Void
    static let moveWindowsToManagedSpace: MoveWindowsFn? =
        sym("CGSMoveWindowsToManagedSpace").map { unsafeBitCast($0, to: MoveWindowsFn.self) }

    static var isAvailable: Bool {
        mainConnectionID != nil && getActiveSpace != nil
            && copySpaces != nil && moveWindowsToManagedSpace != nil
    }
}

/// 비공개 _AXUIElementGetWindow — AXUIElement → CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError
