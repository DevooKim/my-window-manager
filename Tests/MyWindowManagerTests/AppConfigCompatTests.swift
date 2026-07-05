import Testing
import Foundation
@testable import MyWindowManager

struct AppConfigCompatTests {
    // 기존 사용자의 v2 config.json(새 필드 없음)이 기본값으로 디코드돼야 한다.
    @Test func decodingV2ConfigAppliesDefaults() throws {
        let json = #"{"version":2,"presets":[],"layouts":[],"cycles":[]}"#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(AppConfig.self, from: json)
        #expect(cfg.snapSettings.enabled)
        #expect(cfg.snapSettings.restoreOnUnsnap)
        #expect(cfg.sizeBindings == [])
        #expect(cfg.sizeStepRatio == 0.1)
    }

    @Test func roundTripKeepsNewFields() throws {
        var cfg = AppConfig(presets: [], layouts: [], cycles: [], deadzones: [])
        cfg.snapSettings.edgeTop = false
        cfg.sizeStepRatio = 0.15
        cfg.sizeBindings = [SizeBinding(action: .grow, hotkey: nil)]
        let data = try JSONEncoder().encode(cfg)
        let back = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(!back.snapSettings.edgeTop)
        #expect(back.sizeStepRatio == 0.15)
        #expect(back.sizeBindings.count == 1)
        #expect(back.sizeBindings[0].action == .grow)
    }
}
