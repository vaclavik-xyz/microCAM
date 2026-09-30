import AppKit

/// The standard About window (icon, name, version, copyright from
/// `NSHumanReadableCopyright`) with a short description and links. Kept as
/// the system panel, as the HIG recommends.
enum AboutPanel {
    static let repository = URL(string: "https://github.com/vaclavik-xyz/microCAM")!
    static let issues = URL(string: "https://github.com/vaclavik-xyz/microCAM/issues")!
    static let author = URL(string: "https://macdoktor.cz")!

    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func credits() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let text = NSMutableAttributedString()
        func add(_ string: String, link: URL? = nil, color: NSColor? = nil) {
            var attributes = body
            if let link { attributes[.link] = link }
            if let color { attributes[.foregroundColor] = color }
            text.append(NSAttributedString(string: string, attributes: attributes))
        }
        add(String(localized: "Live picture, photos and video from a microscope camera.") + "\n")
        add(String(localized: "Source code on GitHub"), link: repository)
        add("  ·  ")
        add(String(localized: "Report a problem"), link: issues)
        add("\n")
        add(String(localized: "Made by the repair shop") + " ", color: .secondaryLabelColor)
        add("macdoktor.cz", link: author)
        return text
    }
}
