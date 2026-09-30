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
        Group {
            if library.files.isEmpty {
                VStack(spacing: 0) {
                    folderRow.padding(.horizontal, 10)
                    Text("Photos and videos you take appear here.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    folderRow
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
                    .padding(.bottom, 10)
                }
                .contentMargins(.horizontal, 10, for: .scrollContent)
                // A click next to the tiles clears the selection.
                .background(Color.clear.contentShape(Rectangle()).onTapGesture { library.grid = GridSelection() })
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !library.selection.isEmpty {
                selectionBar
                    .padding(8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: library.selection.isEmpty)
    }

    /// Where captures go now, with the file count; click opens it in Finder.
    private var folderRow: some View {
        Button { model.revealCaptureFolder() } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").foregroundStyle(.tint)
                Group {
                    if let name = model.captureFolder?.lastPathComponent {
                        Text(verbatim: name)
                    } else {
                        Text("Not chosen")
                    }
                }
                .font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(verbatim: "\(library.files.count)")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .help("Open the folder where captures are saved now")
    }

    /// Actions for the selected files; shown only while something is selected.
    private var selectionBar: some View {
        HStack(spacing: 6) {
            // Count in the selection colour; the full text is in the tooltip,
            // "Selected: 2" doesn't fit a narrow panel.
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                Text(verbatim: "\(library.selection.count)").monospacedDigit()
            }
            .font(.callout.weight(.medium)).fixedSize()
            .help("Selected: \(library.selection.count)")
            Spacer(minLength: 4)
            if comparePair != nil {
                Button { compare = comparePair } label: { BarIcon("rectangle.split.2x1") }
                    .help("Compare the two photos")
            }
            // The share symbol's box sits low under its arrow; lift it so the centres of the
            // boxes line up with the other icons.
            ShareLink(items: library.selectedFiles) { BarIcon("square.and.arrow.up", lift: 2.5) }
                .help("Share (AirDrop, Mail, Messages…)")
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
                } label: { BarIcon("ellipsis.circle") }
                .menuStyle(.button).menuIndicator(.hidden).fixedSize()
                .help("More actions for the selected files")
            }
            // Grey filled circle, like the clear button of a search field.
            Button { library.grid = GridSelection() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
                .help("Clear selection")
        }
        // Own style: keeps the label colour (.borderless draws icons grey here)
        // and highlights on hover like toolbar buttons.
        .buttonStyle(BarButtonStyle())
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
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

/// Selection-bar buttons: a soft rounded highlight on hover, a stronger one
/// while pressed, as toolbar buttons do.
private struct BarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BarButton(configuration: configuration)
    }

    private struct BarButton: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.08 : 0))
                )
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// Same size and box for every icon in the selection bar. Active controls
/// use the normal label colour; grey (secondary) reads as disabled on macOS.
private struct BarIcon: View {
    let name: String
    var lift: CGFloat = 0

    init(_ name: String, lift: CGFloat = 0) {
        self.name = name
        self.lift = lift
    }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 15))
            .foregroundStyle(.primary)
            .offset(y: -lift)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
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
