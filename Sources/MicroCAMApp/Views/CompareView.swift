import AppKit
import ImageIO
import SwiftUI

/// Loading state of one compared photo.
private enum LoadedImage {
    case loading
    case loaded(NSImage)
    case failed

    /// Decodes fully off the main thread so opening the sheet never stalls the UI.
    static func load(_ url: URL) async -> LoadedImage {
        let cgImage = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }.value
        guard let cgImage else { return .failed }
        return .loaded(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
    }
}

struct CompareView: View {
    let before: URL
    let after: URL
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var split: CGFloat = 0.5
    @State private var beforeImage = LoadedImage.loading
    @State private var afterImage = LoadedImage.loading

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("", selection: $mode) {
                    Text("Vedle sebe").tag(0)
                    Text("Posuvník").tag(1)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                Spacer()
                Button("Zavřít") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if mode == 0 {
                HStack(spacing: 8) {
                    labeled(beforeImage, "Před", before)
                    labeled(afterImage, "Po", after)
                }
            } else {
                GeometryReader { geo in
                    ZStack {
                        picture(afterImage)
                        picture(beforeImage)
                            .mask(alignment: .leading) { Rectangle().frame(width: geo.size.width * split) }
                        Rectangle().fill(.white).frame(width: 2)
                            .position(x: geo.size.width * split, y: geo.size.height / 2)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        split = min(max(value.location.x / geo.size.width, 0), 1)
                    })
                }
                HStack { Text("Před"); Spacer(); Text("Po") }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 600)
        .task {
            async let b = LoadedImage.load(before)
            async let a = LoadedImage.load(after)
            (beforeImage, afterImage) = await (b, a)
        }
    }

    private func picture(_ image: LoadedImage) -> some View {
        Group {
            switch image {
            case .loading: ProgressView()
            case .loaded(let nsImage): Image(nsImage: nsImage).resizable().scaledToFit()
            case .failed:
                Label("Soubor nelze načíst (přesunutý nebo smazaný?)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func labeled(_ image: LoadedImage, _ title: String, _ url: URL) -> some View {
        VStack(spacing: 4) {
            picture(image)
            Text("\(title): \(url.lastPathComponent)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
