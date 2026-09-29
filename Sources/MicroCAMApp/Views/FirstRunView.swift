import SwiftUI

struct FirstRunView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Kam ukládat fotky a videa?").font(.title2.weight(.semibold))
            Text("Vyber složku. microCAM do ní ukládá všechno a jinou si sám nevybere. Kdykoli ji změníš v Nastavení.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Použít Obrázky/microCAM") { model.useDefaultStorageRoot() }
                Spacer()
                Button("Vybrat složku…") { model.chooseStorageRoot() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
