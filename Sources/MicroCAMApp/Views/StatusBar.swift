import SwiftUI

/// Short messages and (Task 13) the recording timer. Deliberately no save
/// path here: the user found it a waste of space; the path lives in Settings.
struct StatusBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
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
