import SwiftUI

/// Short messages over the preview. Information hides after a few seconds;
/// errors stay until closed or replaced.
struct MessageToast: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let message = model.message {
            HStack(spacing: 8) {
                if message.isError {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                Text(message.text)
                    .lineLimit(3).multilineTextAlignment(.leading)
                if message.isError {
                    Button { model.message = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .help("Close")
                }
            }
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
            .frame(maxWidth: 560)
            .id(message.id)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: message.id) {
                guard !message.isError else { return }
                try? await Task.sleep(for: .seconds(4))
                if model.message?.id == message.id {
                    withAnimation { model.message = nil }
                }
            }
        }
    }
}
