import Testing
import Foundation
@testable import MyWindowManager

struct SnapSettingsTests {
    @Test func defaultsAreAllOn() {
        let s = SnapSettings()
        #expect(s.enabled)
        #expect(s.edgeLeft)
        #expect(s.edgeRight)
        #expect(s.edgeTop)
        #expect(s.edgeBottom)
        #expect(s.corners)
        #expect(s.preview)
        #expect(s.restoreOnUnsnap)
    }

    // 필드가 일부만 있는 JSON(장래 필드 추가 대비)도 기본값으로 채워져야 한다.
    @Test func decodesPartialJSON() throws {
        let json = #"{"enabled":false,"corners":false}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(SnapSettings.self, from: json)
        #expect(!s.enabled)
        #expect(!s.corners)
        #expect(s.preview)
        #expect(s.edgeLeft)
    }

    @Test func roundTrip() throws {
        var s = SnapSettings()
        s.edgeTop = false
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SnapSettings.self, from: data)
        #expect(s == back)
    }
}
