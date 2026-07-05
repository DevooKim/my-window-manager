import Testing
import CoreGraphics
@testable import MyWindowManager

@Test func sanity() {
    #expect(RelativeFrame.leftHalf.resolve(in: CGRect(x: 0, y: 0, width: 100, height: 100)).width == 50)
}
