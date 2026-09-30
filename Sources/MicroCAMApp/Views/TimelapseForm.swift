import MicroCAMCore
import SwiftUI

/// Number + unit editor for a duration stored in seconds. Units are
/// abbreviations (s, min, h), so no plural forms are needed after a number.
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
        DurationField(title: Text("Interval"), seconds: seconds, units: [(Text("s"), 1), (Text("min"), 60)])
    }

    static func duration(_ seconds: Binding<TimeInterval>) -> DurationField {
        DurationField(title: Text("Duration"), seconds: seconds, units: [(Text("min"), 60), (Text("h"), 3600)])
    }
}

/// Before start: the two durations, what they add up to, and a large Start
/// button. While running: progress, the next photo and the end, and Stop.
struct TimelapseForm: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var runner: TimelapseRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Timelapse").font(.headline)
                Text("Takes a photo at a fixed interval into the current folder.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if runner.isRunning, let schedule = runner.schedule, let started = runner.startedAt {
                running(schedule, started: started)
            } else {
                setup
            }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 8) {
                DurationField.interval($model.settings.timelapseInterval)
                DurationField.duration($model.settings.timelapseDuration)
            }
            let schedule = TimelapseSchedule(interval: model.settings.timelapseInterval,
                                             duration: model.settings.timelapseDuration)
            Group {
                if let schedule {
                    Text("Photos: \(schedule.shotCount) · done around \(Self.time(schedule.lastShot(startedAt: Date())))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("The interval must be at least 1 second, the duration at least one interval and at most 7 days.")
                        .foregroundStyle(.red)
                }
            }
            .font(.callout).fixedSize(horizontal: false, vertical: true)
            // Closes once it runs; progress shows in the window subtitle.
            // A rejected schedule leaves it open next to the error.
            Button {
                model.startTimelapse()
                if runner.isRunning { model.showTimelapse = false }
            } label: {
                Text("Start timelapse").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(schedule == nil || model.engine.currentCameraID == nil)
        }
    }

    private func running(_ schedule: TimelapseSchedule, started: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "\(runner.shotsTaken)")
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                Text("of \(schedule.shotCount)").font(.title3).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(runner.shotsTaken), total: Double(schedule.shotCount))
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    if let next = schedule.nextShot(startedAt: started, shotsTaken: runner.shotsTaken) {
                        Text("Next photo in \(Self.countdown(to: next, from: context.date))")
                            .monospacedDigit()
                    }
                    Text("Done around \(Self.time(schedule.lastShot(startedAt: started)))")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            Button(role: .destructive) {
                model.stopTimelapse()
                model.showTimelapse = false
            } label: {
                Text("Stop timelapse").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(.red).controlSize(.large)
            .padding(.top, 4)
        }
    }

    /// "16:42", with the day when it isn't today.
    private static func time(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    /// "0:34", "12:05", "1:02:30".
    private static func countdown(to date: Date, from now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
