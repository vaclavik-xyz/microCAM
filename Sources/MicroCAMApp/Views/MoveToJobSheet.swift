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
            Text("Přesunout \(files.count) soubor(ů) k zakázce").font(.headline)
            TextField("např. PR-260042", text: $draft).textFieldStyle(.roundedBorder).onSubmit(moveToJob)
            if invalid { Text("Jen písmena, číslice a pomlčka.").font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Bez zakázky") { model.moveFiles(files, to: .unassigned); dismiss() }
                Spacer()
                Button("Zrušit", role: .cancel) { dismiss() }
                Button("Přesunout", action: moveToJob).keyboardShortcut(.defaultAction)
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
