import SwiftUI

/// Number + unit editor for a duration stored in seconds.
struct DurationField: View {
    let title: Text
    @Binding var seconds: TimeInterval
    let units: [(name: Text, seconds: Double)]
    @State private var unitIndex = 0

    var body: some View {
        HStack {
            title.frame(minWidth: 90, alignment: .leading)
            Spacer(minLength: 0)
            TextField(value: Binding(
                get: { seconds / units[unitIndex].seconds },
                set: { seconds = max(0, $0) * units[unitIndex].seconds }
            ), format: .number.precision(.fractionLength(0...1))) { title }
            .labelsHidden()
            .frame(width: 70)
            Picker(selection: $unitIndex) {
                ForEach(units.indices, id: \.self) { units[$0].name.tag($0) }
            } label: { title }
            .labelsHidden().frame(width: 100)
        }
        .onAppear {
            // Largest unit that divides the stored value evenly.
            unitIndex = units.indices.last { seconds.truncatingRemainder(dividingBy: units[$0].seconds) == 0 } ?? 0
        }
    }

    static func interval(_ seconds: Binding<TimeInterval>) -> DurationField {
        DurationField(title: Text("Every"), seconds: seconds, units: [(Text("seconds"), 1), (Text("minutes"), 60)])
    }

    static func duration(_ seconds: Binding<TimeInterval>) -> DurationField {
        DurationField(title: Text("For"), seconds: seconds, units: [(Text("minutes"), 60), (Text("hours"), 3600)])
    }
}

struct TimelapseForm: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var runner: TimelapseRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Takes a photo at a fixed interval into the active job.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DurationField.interval($model.settings.timelapseInterval)
            DurationField.duration($model.settings.timelapseDuration)
            if runner.isRunning, let schedule = runner.schedule {
                ProgressView(value: Double(runner.shotsTaken), total: Double(schedule.shotCount)) {
                    Text("Photos: \(runner.shotsTaken) of \(schedule.shotCount)")
                }
                Button("Stop timelapse") { model.stopTimelapse() }
            } else {
                Button("Start timelapse") { model.startTimelapse() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.engine.currentCameraID == nil)
            }
        }
    }
}
