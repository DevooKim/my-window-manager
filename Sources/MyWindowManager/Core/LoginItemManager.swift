import Foundation
import ServiceManagement

/// 맥 로그인 시 자동 실행(로그인 항목) 관리. 시스템(SMAppService)이 상태의
/// 유일한 원천이므로 config에는 저장하지 않는다 — 시스템 설정 > 일반 >
/// 로그인 항목에서 사용자가 직접 바꿔도 어긋나지 않는다.
enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 등록/해제. 실패 시 throw — 호출부에서 알림 + 토글 롤백.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
