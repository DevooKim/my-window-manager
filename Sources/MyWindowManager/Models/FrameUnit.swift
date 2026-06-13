import Foundation
import CoreGraphics

enum FrameUnitType: String, Codable, CaseIterable, Identifiable {
    case ratio
    case pixels
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ratio: return "ratio"
        case .pixels: return "px"
        }
    }
}

enum FrameUnit: Codable, Hashable {
    case ratio(Double)
    case pixels(CGFloat)

    var type: FrameUnitType {
        switch self {
        case .ratio: return .ratio
        case .pixels: return .pixels
        }
    }

    var rawValue: Double {
        switch self {
        case .ratio(let r): return r
        case .pixels(let px): return Double(px)
        }
    }

    func resolve(in total: CGFloat) -> CGFloat {
        switch self {
        case .ratio(let r): return total * CGFloat(r)
        case .pixels(let px): return px
        }
    }

    func converted(to type: FrameUnitType, total: CGFloat) -> FrameUnit {
        let px = resolve(in: total)
        switch type {
        case .ratio:
            let denom = total == 0 ? 1 : total
            return .ratio(Double(px / denom))
        case .pixels:
            return .pixels(px)
        }
    }

    static func of(type: FrameUnitType, value: Double) -> FrameUnit {
        switch type {
        case .ratio: return .ratio(value)
        case .pixels: return .pixels(CGFloat(value))
        }
    }

    private enum CodingKeys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(FrameUnitType.self, forKey: .type)
        let value = try c.decode(Double.self, forKey: .value)
        self = .of(type: type, value: value)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(rawValue, forKey: .value)
    }
}

struct RelativeFrame: Codable, Hashable {
    var x: FrameUnit
    var y: FrameUnit
    var width: FrameUnit
    var height: FrameUnit

    static let fullScreen = RelativeFrame(
        x: .ratio(0), y: .ratio(0),
        width: .ratio(1.0), height: .ratio(1.0)
    )

    static let leftHalf = RelativeFrame(
        x: .ratio(0), y: .ratio(0),
        width: .ratio(0.5), height: .ratio(1.0)
    )

    func resolve(in area: CGRect) -> CGRect {
        CGRect(
            x: area.minX + x.resolve(in: area.width),
            y: area.minY + y.resolve(in: area.height),
            width: width.resolve(in: area.width),
            height: height.resolve(in: area.height)
        )
    }
}
