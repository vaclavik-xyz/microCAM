import AppKit
import SwiftUI

struct JobBar: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""
    @State private var invalid = false

    var body: some View {
        HStack(spacing: 8) {
            Text("Zakázka:")
            TextField("např. PR-260042", text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit(apply)
            Button("Nastavit", action: apply)
            Button("Bez zakázky") { draft = ""; apply() }
                .disabled(model.settings.activeJob == nil)
            if invalid {
                Text("Jen písmena, číslice a pomlčka.").font(.caption).foregroundStyle(.red)
            }
            Spacer()
            Text(model.settings.activeJob.map { "Aktivní: \($0.value)" } ?? "Aktivní: bez zakázky")
                .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .onAppear { draft = model.settings.activeJob?.value ?? "" }
    }

    private func apply() {
        invalid = !model.setActiveJob(draft)
        guard !invalid else { return }
        draft = model.settings.activeJob?.value ?? ""
        // Leave the text field so single-key shortcuts work again.
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}
