import AppKit
import MicroCAMCore
import SwiftUI

struct ComparePair: Identifiable {
    let before: URL
    let after: URL
    var id: String { before.path + "|" + after.path }
}

/// Grid of the current folder's captures, grouped by day. Click selects,
/// ⌘-click adds, ⇧-click selects a range, double-click opens, drag copies
/// the file into another app.
struct SidePanel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var library: LibraryModel
    @Binding var compare: ComparePair?

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 160), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            if library.files.isEmpty {
                Text("Photos and videos you take appear here.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(CaptureDays.group(library.files), id: \.day) { day in
                            Section {
                                ForEach(day.files, id: \.self) { url in
                                    CaptureTile(url: url, library: library, selected: library.selection.contains(url))
                                        .onTapGesture { click(url) }
                                        .contextMenu { menu(for: library.grid.targets(forContextClickOn: url, in: library.files)) }
                                        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                                }
                            } header: {
                                DayHeader(day: day.day)
                            }
                        }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 10)
                }
                // A click next to the tiles clears the selection.
                .background(Color.clear.contentShape(Rectangle()).onTapGesture { library.grid = GridSelection() })
            }
            Divider()
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Files: \(library.files.count)").font(.caption).foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 4)
            Button { model.revealCaptureFolder() } label: { Image(systemName: "folder") }
                .help("Open the folder where captures are saved now")
            ShareLink(items: library.selectedFiles) { Image(systemName: "square.and.arrow.up") }
                .disabled(library.selection.isEmpty)
                .help("Share (AirDrop, Mail, Messages…)")
            Button { compare = comparePair } label: { Image(systemName: "rectangle.split.2x1") }
                .disabled(comparePair == nil)
                .help("Select two photos to compare them")
            if model.settings.jobsEnabled || model.webhookEndpoint != nil {
                Menu {
                    if model.settings.jobsEnabled {
                        Button("Move to job…") { model.filesToMove = library.selectedFiles }
                            .disabled(model.isMovingFiles)
                    }
                    if model.webhookEndpoint != nil {
                        Button("Send to webhook") { model.sendToWebhook(library.selectedFiles) }
                            .disabled(model.isSending)
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuIndicator(.hidden).fixedSize()
                .disabled(library.selection.isEmpty)
                .help("More actions for the selected files")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    @ViewBuilder
    private func menu(for urls: [URL]) -> some View {
        Button("Open") { urls.forEach { NSWorkspace.shared.open($0) } }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        ShareLink("Share…", items: urls)
        if model.webhookEndpoint != nil {
            Button("Send to webhook") { model.sendToWebhook(urls) }
        }
        if model.settings.jobsEnabled {
            Button("Move to job…") { model.filesToMove = urls }
        }
    }

    private func click(_ url: URL) {
        let event = NSApp.currentEvent
        if (event?.clickCount ?? 1) >= 2 {
            NSWorkspace.shared.open(url)
            return
        }
        let flags = event?.modifierFlags ?? []
        library.grid.click(url, in: library.files, command: flags.contains(.command), shift: flags.contains(.shift))
    }

    /// Exactly two photos, older one first ("before"). Sorted by the timestamp
    /// in the name, not the whole name (the prefix differs after a move).
    private var comparePair: ComparePair? {
        let photos = library.selection.filter { $0.pathExtension.lowercased() == "jpg" }
        guard library.selection.count == 2, photos.count == 2 else { return nil }
        let key = { (url: URL) in CaptureFileName.parse(url.lastPathComponent)?.timestamp ?? url.lastPathComponent }
        let sorted = photos.sorted { key($0) < key($1) }
        return ComparePair(before: sorted[0], after: sorted[1])
    }
}

private struct DayHeader: View {
    let day: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8).padding(.bottom, 2)
    }

    private var title: String {
        guard let date = CaptureDays.date(ofDay: day) else { return String(localized: "Other files") }
        if Calendar.current.isDateInToday(date) { return String(localized: "Today") }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }
}

private struct CaptureTile: View {
    let url: URL
    @ObservedObject var library: LibraryModel
    let selected: Bool
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 3) {
            // Fixed 4:3 cell; the thumbnail fills it without widening the grid.
            Color.secondary.opacity(0.15)
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay {
                    if let image { Image(nsImage: image).resizable().scaledToFill() }
                }
                .overlay(alignment: .bottomLeading) {
                    if url.pathExtension.lowercased() == "mov" {
                        Image(systemName: "video.fill")
                            .font(.caption2).foregroundStyle(.white)
                            .padding(4).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                            .padding(4)
                    }
                }
                .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 3 : 1))
            Text(CaptureDays.timeOfDay(url))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .help(url.lastPathComponent)
        .task(id: url) { image = await library.thumbnail(for: url) }
    }
}
