import AppKit
import SwiftUI

/// The active job in the toolbar; click to change it. Shown only when jobs
/// are on (Settings → Storage).
struct JobToolbarButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var show = false

    var body: some View {
        Button { show.toggle() } label: {
            // Titled "Job" for Customize Toolbar, which names items by the
            // label's title; the toolbar itself shows the job code.
            Label("Job", systemImage: "tag")
                .labelStyle(JobLabelStyle(code: model.settings.activeJob?.value ?? String(localized: "No job")))
        }
        .help("Job: files go into its folder")
        .popover(isPresented: $show, arrowEdge: .bottom) {
            JobForm { show = false }.padding(16).frame(width: 300)
        }
    }
}

private struct JobLabelStyle: LabelStyle {
    let code: String

    func makeBody(configuration: Configuration) -> some View {
        Label { Text(verbatim: code) } icon: { configuration.icon }
            .labelStyle(.titleAndIcon)
    }
}

private struct JobForm: View {
    @EnvironmentObject private var model: AppModel
    let done: () -> Void
    @State private var draft = ""
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Job").font(.headline)
            TextField("e.g. PR-260042", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(apply)
            if invalid {
                Text("Use only letters, digits and hyphens.").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("No job") { draft = ""; apply() }
                    .disabled(model.settings.activeJob == nil)
                Spacer()
                Button("Set", action: apply).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { draft = model.settings.activeJob?.value ?? "" }
    }

    private func apply() {
        invalid = !model.setActiveJob(draft)
        guard !invalid else { return }
        done()
        // Give the keyboard back to the main window so Space/R/G work again.
        model.mainWindow?.makeFirstResponder(nil)
    }
}
