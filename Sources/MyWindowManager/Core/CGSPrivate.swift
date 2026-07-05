import Foundation
import CoreGraphics
import ApplicationServices
import Darwin
import ObjectiveC

/// 비공개 CGS/SkyLight 접근. macOS 26 Tahoe에서 창을 다른 space로 옮기는
/// 유일하게 동작하는(SIP 켜진 채) 경로는 yabai v7.1.25가 발견한
/// `SLSPerformAsynchronousBridgedWindowManagementOperation` +
/// ObjC 클래스 `SLSBridgedMoveWindowsToManagedSpaceOperation` 조합이다.
///
/// 이 함수는 export 심볼이 아니라 SkyLight Mach-O 심볼 테이블의 mangled static
/// 심볼(`__ZL54...`)이라 dlsym으로는 못 찾는다. 로드된 이미지의 LC_SYMTAB을
/// 직접 순회해 주소를 얻는다.
enum CGSPrivate {
    typealias ConnID = UInt32
    typealias SpaceID = UInt64

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static func sym(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(handle, name) ?? dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    }

    // MARK: - Connection

    typealias MainConnectionFn = @convention(c) () -> ConnID
    static let mainConnectionID: MainConnectionFn? =
        sym("SLSMainConnectionID").map { unsafeBitCast($0, to: MainConnectionFn.self) }
        ?? sym("CGSMainConnectionID").map { unsafeBitCast($0, to: MainConnectionFn.self) }

    // MARK: - Space 목록 (display별, type 포함)

    typealias CopyManagedDisplaySpacesFn = @convention(c) (ConnID) -> Unmanaged<CFArray>?
    static let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn? =
        sym("SLSCopyManagedDisplaySpaces").map { unsafeBitCast($0, to: CopyManagedDisplaySpacesFn.self) }

    // MARK: - Window이 속한 Space

    typealias CopySpacesForWindowsFn = @convention(c) (ConnID, Int32, CFArray) -> Unmanaged<CFArray>?
    static let copySpacesForWindows: CopySpacesForWindowsFn? =
        sym("SLSCopySpacesForWindows").map { unsafeBitCast($0, to: CopySpacesForWindowsFn.self) }
        ?? sym("CGSCopySpacesForWindows").map { unsafeBitCast($0, to: CopySpacesForWindowsFn.self) }

    // MARK: - Bridged move (Tahoe SIP-free 경로)

    // int64_t SLSPerformAsynchronousBridgedWindowManagementOperation(void *operation)
    typealias BridgedPerformFn = @convention(c) (UnsafeMutableRawPointer) -> Int64
    static let bridgedPerform: BridgedPerformFn? = {
        guard let addr = MachOSymbol.find(
            image: "SkyLight",
            containing: "SLSPerformAsynchronousBridgedWindowManagementOperation"
        ) else { return nil }
        return unsafeBitCast(addr, to: BridgedPerformFn.self)
    }()

    /// bridged 경로 사용 가능 여부.
    static var bridgedAvailable: Bool {
        bridgedPerform != nil
            && objc_getClass("SLSBridgedMoveWindowsToManagedSpaceOperation") != nil
    }

    /// 창들을 target managed space로 옮긴다(SIP 켜진 채 Tahoe에서 동작).
    /// 성공 시 true. yabai v7.1.25 와 동일하게:
    ///   - window id를 kCFNumberSInt32Type CFNumber로 만든 CFArray
    ///   - [[cls alloc] initWithWindows:array spaceID:(uint64_t)sid]
    ///   - perform(operation) fire-and-forget
    static func bridgedMove(windowIDs: [CGWindowID], to space: SpaceID) -> Bool {
        guard let perform = bridgedPerform,
              let cls = objc_getClass("SLSBridgedMoveWindowsToManagedSpaceOperation") as? AnyClass else {
            return false
        }

        // window id → kCFNumberSInt32Type CFNumber → CFArray
        let numbers: [CFNumber] = windowIDs.map { wid in
            var v = Int32(bitPattern: wid)
            return CFNumberCreate(nil, .sInt32Type, &v)!
        }
        var ptrs: [UnsafeRawPointer?] = numbers.map { UnsafeRawPointer(Unmanaged.passUnretained($0).toOpaque()) }
        let windows = CFArrayCreate(nil, &ptrs, numbers.count, nil)!

        // [[cls alloc] initWithWindows:windows spaceID:space]
        let msgSend = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")!
        typealias AllocFn = @convention(c) (AnyClass, Selector) -> AnyObject
        typealias InitFn = @convention(c) (AnyObject, Selector, CFArray, UInt64) -> AnyObject?
        let allocated = unsafeBitCast(msgSend, to: AllocFn.self)(cls, NSSelectorFromString("alloc"))
        guard let operation = unsafeBitCast(msgSend, to: InitFn.self)(
            allocated, NSSelectorFromString("initWithWindows:spaceID:"), windows, space
        ) else { return false }

        _ = perform(Unmanaged.passUnretained(operation).toOpaque())
        return true
    }

    // 참고: SLSBridgedManagedDisplaySetCurrentSpaceOperation 으로 화면을 직접
    // 전환하면 Dock과 동기화되지 않아 메뉴바/배경이 깨진다. 화면 전환은
    // SpaceMover.followWindow (raise + activate, Dock 주도) 방식을 쓸 것.
}

/// 로드된 이미지의 Mach-O 심볼 테이블(LC_SYMTAB)을 순회해 이름에 특정 문자열을
/// 포함하는 심볼의 런타임 주소를 찾는다. dlsym이 못 잡는 static 심볼용.
enum MachOSymbol {
    static func find(image imageSubstring: String, containing needle: String) -> UnsafeMutableRawPointer? {
        let count = _dyld_image_count()
        for i in 0..<count {
            guard let namePtr = _dyld_get_image_name(i) else { continue }
            let name = String(cString: namePtr)
            guard name.contains(imageSubstring) else { continue }
            guard let mhPtr = _dyld_get_image_header(i) else { continue }
            let slide = _dyld_get_image_vmaddr_slide(i)

            let mh = mhPtr.withMemoryRebound(to: mach_header_64.self, capacity: 1) { $0.pointee }
            guard mh.magic == MH_MAGIC_64 else { continue }

            var cmdPtr = UnsafeRawPointer(mhPtr).advanced(by: MemoryLayout<mach_header_64>.size)
            var symtab: symtab_command?
            var linkeditBase: UInt = 0

            for _ in 0..<mh.ncmds {
                let lc = cmdPtr.load(as: load_command.self)
                if lc.cmd == UInt32(LC_SYMTAB) {
                    symtab = cmdPtr.load(as: symtab_command.self)
                } else if lc.cmd == UInt32(LC_SEGMENT_64) {
                    let seg = cmdPtr.load(as: segment_command_64.self)
                    if segName(seg) == "__LINKEDIT" {
                        linkeditBase = UInt(bitPattern: Int(seg.vmaddr) - Int(seg.fileoff) + slide)
                    }
                }
                cmdPtr = cmdPtr.advanced(by: Int(lc.cmdsize))
            }

            guard let st = symtab, linkeditBase != 0 else { continue }
            let syms = UnsafeRawPointer(bitPattern: linkeditBase + UInt(st.symoff))!
                .assumingMemoryBound(to: nlist_64.self)
            let strs = UnsafeRawPointer(bitPattern: linkeditBase + UInt(st.stroff))!
                .assumingMemoryBound(to: CChar.self)

            for s in 0..<Int(st.nsyms) {
                let strx = syms[s].n_un.n_strx
                guard strx != 0 else { continue }
                let sname = String(cString: strs.advanced(by: Int(strx)))
                if sname.contains(needle) {
                    let addr = UInt(syms[s].n_value) + UInt(bitPattern: slide)
                    return UnsafeMutableRawPointer(bitPattern: addr)
                }
            }
        }
        return nil
    }

    /// segment_command_64.segname (16바이트 char 튜플) → String.
    private static func segName(_ seg: segment_command_64) -> String {
        withUnsafeBytes(of: seg.segname) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}

/// 비공개 _AXUIElementGetWindow — AXUIElement → CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError
