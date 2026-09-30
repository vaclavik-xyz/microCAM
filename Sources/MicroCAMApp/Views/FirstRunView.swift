import SwiftUI

struct FirstRunView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where should microCAM save photos and videos?").font(.title2.weight(.semibold))
            Text("Choose a folder. microCAM saves everything there and never picks a folder on its own. You can change it any time in Settings.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Use Pictures/microCAM") { model.useDefaultStorageRoot() }
                Spacer()
                Button("Choose folder…") { model.chooseStorageRoot() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
