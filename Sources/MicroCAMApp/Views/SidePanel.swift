import AppKit
import MicroCAMCore
import SwiftUI

struct ComparePair: Identifiable {
    let before: URL
    let after: URL
    var id: String { before.path + "|" + after.path }
}

struct SidePanel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var library: LibraryModel
    @Binding var compare: ComparePair?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $library.selection) {
                ForEach(library.files, id: \.self) { url in
                    CaptureRow(url: url, library: library)
                }
            }
            .contextMenu(forSelectionType: URL.self) { urls in
                Button("Otevřít") { urls.forEach { NSWorkspace.shared.open($0) } }
                Button("Zobrazit ve Finderu") { NSWorkspace.shared.activateFileViewerSelecting(Array(urls)) }
                ShareLink("Sdílet…", items: Array(urls))
                if model.webhookEndpoint != nil {
                    Button("Odeslat přes webhook") { model.sendToWebhook(Array(urls)) }
                }
                if model.settings.jobsEnabled {
                    Button("Přesunout k zakázce…") { model.filesToMove = Array(urls) }
                }
            } primaryAction: { urls in
                urls.forEach { NSWorkspace.shared.open($0) }
            }
            Divider()
            HStack {
                Text("\(library.files.count) souborů").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.settings.jobsEnabled {
                    Button("Přesunout…") { model.filesToMove = Array(library.selection) }
                        .disabled(library.selection.isEmpty || model.isMovingFiles)
                }
                ShareLink(items: Array(library.selection)) { Image(systemName: "square.and.arrow.up") }
                    .disabled(library.selection.isEmpty)
                    .help("Sdílet (AirDrop, Mail, Zprávy…)")
                if model.webhookEndpoint != nil {
                    Button("Odeslat") { model.sendToWebhook(Array(library.selection)) }
                        .disabled(library.selection.isEmpty || model.isSending)
                        .help("Odeslat vybrané soubory přes webhook")
                }
                Button("Porovnat") { compare = comparePair }
                    .disabled(comparePair == nil)
                    .help("Vyber dvě fotky")
            }
            .controlSize(.small)
            .padding(8)
        }
    }

    /// Exactly two photos, older one first ("před"). Sorted by the timestamp
    /// in the name, not the whole name (the prefix differs after a move).
    private var comparePair: ComparePair? {
        let photos = library.selection.filter { $0.pathExtension.lowercased() == "jpg" }
        guard library.selection.count == 2, photos.count == 2 else { return nil }
        let key = { (url: URL) in CaptureFileName.parse(url.lastPathComponent)?.timestamp ?? url.lastPathComponent }
        let sorted = photos.sorted { key($0) < key($1) }
        return ComparePair(before: sorted[0], after: sorted[1])
    }
}

private struct CaptureRow: View {
    let url: URL
    @ObservedObject var library: LibraryModel
    @State private var image: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Color.black.opacity(0.2)
                if let image { Image(nsImage: image).resizable().scaledToFit() }
            }
            .frame(width: 96, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(timeLabel).font(.callout.monospacedDigit())
                if url.pathExtension.lowercased() == "mov" {
                    Label("Video", systemImage: "video.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: url) { image = await library.thumbnail(for: url) }
    }

    /// "2026-09-21 14:13:20" from the file name.
    private var timeLabel: String {
        guard let name = CaptureFileName.parse(url.lastPathComponent) else { return url.lastPathComponent }
        let parts = name.timestamp.split(separator: "_")
        guard parts.count == 2 else { return name.timestamp }
        return "\(parts[0]) \(parts[1].replacingOccurrences(of: "-", with: ":"))" + (name.index.map { " (\($0))" } ?? "")
    }
}
