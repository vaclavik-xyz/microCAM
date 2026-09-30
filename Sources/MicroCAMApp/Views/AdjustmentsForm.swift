import MicroCAMCore
import SwiftUI

struct AdjustmentsForm: View {
    @EnvironmentObject private var model: AppModel

    private let rows: [(Text, WritableKeyPath<ImageAdjustments, Double>, String)] = [
        (Text("Brightness"), \.brightness, "%.2f"),
        (Text("Contrast"), \.contrast, "%.2f"),
        (Text("Saturation"), \.saturation, "%.2f"),
        (Text("Temperature"), \.temperature, "%.0f K"),
        (Text("Tint"), \.tint, "%.0f"),
        (Text("Gamma"), \.gamma, "%.2f"),
        (Text("Sharpening"), \.sharpness, "%.2f"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows.indices, id: \.self) { index in
                let (title, path, format) = rows[index]
                HStack {
                    title.frame(width: 90, alignment: .leading)
                    Slider(value: binding(path), in: ImageAdjustments.ranges[path]!)
                    Text(String(format: format, model.currentAdjustments[keyPath: path]))
                        .monospacedDigit().frame(width: 64, alignment: .trailing)
                }
            }
            HStack {
                Text("Saved for this camera. Applies to the preview, photos and videos.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { model.currentAdjustments = .neutral }
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
