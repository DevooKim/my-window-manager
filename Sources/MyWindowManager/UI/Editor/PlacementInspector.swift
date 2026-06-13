import SwiftUI

struct FrameUnitFieldRow: View {
    let label: String
    @Binding var unit: FrameUnit
    let monitorDimension: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 28, alignment: .leading)
                .foregroundStyle(.secondary)
            TextField("", value: Binding(
                get: { unit.rawValue },
                set: { newVal in
                    switch unit {
                    case .ratio: unit = .ratio(newVal)
                    case .pixels: unit = .pixels(CGFloat(newVal))
                    }
                }
            ), format: .number.precision(.fractionLength(0...3)))
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)

            Picker("", selection: Binding(
                get: { unit.type },
                set: { newType in
                    if newType != unit.type {
                        unit = unit.converted(to: newType, total: monitorDimension)
                    }
                }
            )) {
                ForEach(FrameUnitType.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 90)
        }
    }
}

struct RelativeFrameInspector: View {
    @Binding var frame: RelativeFrame
    let monitorSize: CGSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FrameUnitFieldRow(label: "X", unit: $frame.x, monitorDimension: monitorSize.width)
            FrameUnitFieldRow(label: "Y", unit: $frame.y, monitorDimension: monitorSize.height)
            FrameUnitFieldRow(label: "W", unit: $frame.width, monitorDimension: monitorSize.width)
            FrameUnitFieldRow(label: "H", unit: $frame.height, monitorDimension: monitorSize.height)
        }
    }
}
