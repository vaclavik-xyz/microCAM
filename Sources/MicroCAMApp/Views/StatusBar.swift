import SwiftUI

/// Short messages and (Task 13) the recording timer. Deliberately no save
/// path here: the user found it a waste of space; the path lives in Settings.
struct StatusBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            if let started = model.recordingStartedAt {
                TimelineView(.periodic(from: started, by: 1)) { context in
                    let seconds = max(0, Int(context.date.timeIntervalSince(started)))
                    Label(String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60),
                          systemImage: "record.circle.fill")
                        .foregroundStyle(.red).monospacedDigit()
                }
                if model.droppedFrames > 0 {
                    Text("vypadlé snímky: \(model.droppedFrames)").foregroundStyle(.orange)
                }
            }
            Spacer()
            if let message = model.message {
                Text(message.text)
                    .foregroundStyle(message.isError ? Color.red : Color.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10).padding(.vertical, 6)
    }
}
