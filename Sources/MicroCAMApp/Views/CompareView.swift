import AppKit
import SwiftUI

struct CompareView: View {
    let before: URL
    let after: URL
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var split: CGFloat = 0.5
    @State private var beforeImage: NSImage?
    @State private var afterImage: NSImage?

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
            beforeImage = NSImage(contentsOf: before)
            afterImage = NSImage(contentsOf: after)
        }
    }

    private func picture(_ image: NSImage?) -> some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() } else { ProgressView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func labeled(_ image: NSImage?, _ title: String, _ url: URL) -> some View {
        VStack(spacing: 4) {
            picture(image)
            Text("\(title): \(url.lastPathComponent)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
