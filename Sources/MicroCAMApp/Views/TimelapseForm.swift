import SwiftUI

/// Number + unit editor for a duration stored in seconds.
struct DurationField: View {
    let title: String
    @Binding var seconds: TimeInterval
    let units: [(name: String, seconds: Double)]
    @State private var unitIndex = 0

    var body: some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            TextField("", value: Binding(
                get: { seconds / units[unitIndex].seconds },
                set: { seconds = max(0, $0) * units[unitIndex].seconds }
            ), format: .number.precision(.fractionLength(0...1)))
            .frame(width: 70)
            Picker("", selection: $unitIndex) {
                ForEach(units.indices, id: \.self) { Text(units[$0].name).tag($0) }
            }
            .labelsHidden().frame(width: 90)
        }
        .onAppear {
            // Largest unit that divides the stored value evenly.
            unitIndex = units.indices.last { seconds.truncatingRemainder(dividingBy: units[$0].seconds) == 0 } ?? 0
        }
    }
}

struct TimelapseForm: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var runner: TimelapseRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DurationField(title: "Fotit každých", seconds: $model.settings.timelapseInterval,
                          units: [("sekund", 1), ("minut", 60)])
            DurationField(title: "Po dobu", seconds: $model.settings.timelapseDuration,
                          units: [("minut", 60), ("hodin", 3600)])
            if runner.isRunning, let schedule = runner.schedule {
                ProgressView(value: Double(runner.shotsTaken), total: Double(schedule.shotCount)) {
                    Text("\(runner.shotsTaken) / \(schedule.shotCount) snímků")
                }
                Button("Zastavit časosběr") { model.stopTimelapse() }
            } else {
                Button("Spustit časosběr") { model.startTimelapse() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.engine.currentCameraID == nil)
            }
        }
    }
}
