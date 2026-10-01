import MicroCAMCore
import SwiftUI

/// Tools for drawing on the live picture, floating at the bottom of the
/// preview while drawing (D). What is drawn stays until it is deleted, and
/// photos carry it.
struct DrawingPalette: View {
    @EnvironmentObject private var model: AppModel

    private let tools: [(kind: AnnotationShape.Kind, symbol: String, title: LocalizedStringKey)] = [
        (.arrow, "arrow.up.right", LocalizedStringKey("Arrow")),
        (.ellipse, "circle", LocalizedStringKey("Circle")),
        (.pen, "scribble", LocalizedStringKey("Pen")),
        (.text, "textformat", LocalizedStringKey("Text")),
        (.pointer, "cursorarrow.rays", LocalizedStringKey("Pointer – fades after a moment")),
    ]
    private let colorNames = [LocalizedStringKey("Red"), LocalizedStringKey("Yellow"), LocalizedStringKey("Green"),
                              LocalizedStringKey("Blue")]

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(tools, id: \.kind) { tool in
                    let selected = model.drawTool == tool.kind
                    Button { model.drawTool = tool.kind } label: {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 30, height: 28)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tool.title)
                    .accessibilityLabel(tool.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Divider().frame(height: 20)
            HStack(spacing: 4) {
                ForEach(Array(AppModel.drawColors.enumerated()), id: \.element) { index, hex in
                    let selected = model.drawColor == hex
                    Button { model.drawColor = hex } label: {
                        Circle().fill(Color(nsColor: NSColor(hex: hex)))
                            .frame(width: 18, height: 18)
                            .padding(3)
                            .overlay(Circle().strokeBorder(selected ? Color.primary : .clear, lineWidth: 2))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(colorNames[index])
                    .accessibilityLabel(colorNames[index])
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if model.drawTool == .text {
                Divider().frame(height: 20)
                Picker("Text size", selection: $model.textSize) {
                    Image(systemName: "textformat.size.smaller").accessibilityLabel("Small text")
                        .tag(AnnotationTextSize.small)
                    Image(systemName: "textformat.size").accessibilityLabel("Medium text")
                        .tag(AnnotationTextSize.medium)
                    Image(systemName: "textformat.size.larger").accessibilityLabel("Large text")
                        .tag(AnnotationTextSize.large)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Text size")
            }
            Divider().frame(height: 20)
            Button { model.undoDrawing() } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 26, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canUndoDrawing)
            .help("Undo last drawing")
            .accessibilityLabel("Undo last drawing")
            Button { model.clearDrawing() } label: {
                Image(systemName: "trash").frame(width: 26, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.hasDrawing)
            .help("Clear all drawings")
            .accessibilityLabel("Clear all drawings")
            Divider().frame(height: 20)
            Button("Done") { model.isDrawing = false }
                .help("Stop drawing (Esc)")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drawing")
    }
}
