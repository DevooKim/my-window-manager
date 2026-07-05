# 로그인 시 자동 실행 설계

날짜: 2026-07-06
상태: 승인됨

## 개요

맥이 켜질 때(로그인 시) 앱이 자동 실행되는 기능과, 이를 켜고 끄는 설정 토글을
추가한다.

## 설계

- **API**: `SMAppService.mainApp`(ServiceManagement, macOS 13+). 헬퍼 앱 없이
  현재 앱 번들을 로그인 항목으로 `register()`/`unregister()`.
- **상태 원천**: 시스템(`SMAppService.mainApp.status == .enabled`)이 유일한
  원천 — config.json에 저장하지 않는다. 시스템 설정 > 일반 > 로그인 항목에서
  사용자가 직접 바꿔도 어긋나지 않도록, 일반 탭이 나타날 때마다 재조회한다.
- **컴포넌트**: `Core/LoginItemManager.swift` — `isEnabled` 조회와
  `setEnabled(_:) throws` 두 개짜리 얇은 래퍼(enum).
- **UI**: 일반 탭(GeneralView) 첫 섹션에 "맥 시작 시 자동 실행" 토글.
  등록/해제 실패 시 기존 `presentError` 패턴으로 알림 후 토글 롤백.
  footer에 시스템 설정 > 로그인 항목에서도 제어 가능함을 안내.

## 범위 제외

- config 저장/백업 포함 (시스템이 원천이므로 불필요)
- 백그라운드 시작 시 설정 창 숨김 등 시작 동작 변경 (현행 유지)

## 테스트

시스템 로그인 항목 상태에 의존하므로 단위 테스트 없음. 수동 확인:
토글 on → 시스템 설정 > 일반 > 로그인 항목에 앱 표시, off → 사라짐.
