import MicroCAMCore
import SwiftUI

struct MoveToJobSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let files: [URL]
    @State private var draft = ""
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move to job").font(.headline)
            Text("Selected files: \(files.count)").foregroundStyle(.secondary)
            TextField("e.g. PR-260042", text: $draft).textFieldStyle(.roundedBorder).onSubmit(moveToJob)
            if invalid { Text("Use only letters, digits and hyphens.").font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Move to Unsorted") { model.moveFiles(files, to: .unassigned); dismiss() }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Move", action: moveToJob).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func moveToJob() {
        guard let code = JobCode(draft) else { invalid = true; return }
        model.moveFiles(files, to: .job(code))
        dismiss()
    }
}
