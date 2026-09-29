import MicroCAMCore
import SwiftUI

struct AdjustmentsForm: View {
    @EnvironmentObject private var model: AppModel

    private let rows: [(String, WritableKeyPath<ImageAdjustments, Double>, String)] = [
        ("Jas", \.brightness, "%.2f"),
        ("Kontrast", \.contrast, "%.2f"),
        ("Sytost", \.saturation, "%.2f"),
        ("Teplota", \.temperature, "%.0f K"),
        ("Odstín", \.tint, "%.0f"),
        ("Gama", \.gamma, "%.2f"),
        ("Doostření", \.sharpness, "%.2f"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows, id: \.0) { title, path, format in
                HStack {
                    Text(title).frame(width: 80, alignment: .leading)
                    Slider(value: binding(path), in: ImageAdjustments.ranges[path]!)
                    Text(String(format: format, model.currentAdjustments[keyPath: path]))
                        .monospacedDigit().frame(width: 64, alignment: .trailing)
                }
            }
            HStack {
                Text("Ukládá se pro tuto kameru.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Obnovit výchozí") { model.currentAdjustments = .neutral }
                    .disabled(model.currentAdjustments.isNeutral)
            }
        }
        .disabled(model.engine.currentCameraID == nil)
    }

    private func binding(_ path: WritableKeyPath<ImageAdjustments, Double>) -> Binding<Double> {
        Binding(
            get: { model.currentAdjustments[keyPath: path] },
            set: { value in
                var a = model.currentAdjustments
                a[keyPath: path] = value
                model.currentAdjustments = a
            }
        )
    }
}
