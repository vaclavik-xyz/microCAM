import AppKit
import MicroCAMCore
import SwiftUI

/// The search field at the top of the side panel, while jobs are on. Typing
/// lists the job folders whose code matches; a click switches to that job.
struct JobSearchField: ViewModifier {
    let enabled: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, placement: .sidebar, prompt: Text("Find a job"))
        } else {
            content
        }
    }
}

struct JobSearchResults: View {
    @EnvironmentObject private var model: AppModel
    @Binding var query: String
    @State private var jobs: [JobSummary]?

    var body: some View {
        Group {
            if let jobs {
                let found = JobFinder.filter(jobs, query: query)
                if found.isEmpty {
                    ContentUnavailableView.search(text: query.trimmingCharacters(in: .whitespaces))
                } else {
                    List(found, id: \.code) { job in
                        JobRow(job: job, current: job.code == model.settings.activeJob)
                            .contentShape(Rectangle())
                            .onTapGesture { open(job) }
                            .contextMenu {
                                Button("Switch to this job") { open(job) }
                                Button("Show in Finder") { reveal(job) }
                            }
                    }
                    .listStyle(.sidebar)
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Read the folders once per search; typing only filters them.
        .task(id: model.captureRevision) {
            guard let layout = model.layout else { return jobs = [] }
            jobs = await Task.detached(priority: .userInitiated) { JobFinder.jobs(in: layout) }.value
        }
    }

    private func open(_ job: JobSummary) {
        _ = model.setActiveJob(job.code.value)
        query = ""
        model.mainWindow?.makeFirstResponder(nil)
    }

    private func reveal(_ job: JobSummary) {
        guard let folder = model.layout?.baseFolder(for: .job(job.code)) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}

private struct JobRow: View {
    let job: JobSummary
    let current: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: current ? "checkmark.circle.fill" : "tag").foregroundStyle(.tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: job.code.value).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .help(current ? String(localized: "The current job") : String(localized: "Click to switch to this job"))
    }

    private var detail: String {
        let files = String(localized: "Files: \(job.files)")
        guard let day = job.lastDay.flatMap({ CaptureDays.date(ofDay: $0) }) else { return files }
        return files + " · " + day.formatted(date: .abbreviated, time: .omitted)
    }
}
