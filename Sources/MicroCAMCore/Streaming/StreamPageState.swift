import Foundation

/// What the stream page reports to microCAM's viewer whenever it changes
/// (`report()` in StreamPage, posted to the `microcam` message handler), so the
/// viewer's native tools show the page's drawing state.
public struct StreamPageState: Decodable, Equatable, Sendable {
    public let drawing: Bool
    /// An `AnnotationShape.Kind` raw value.
    public let tool: String
    /// "#ff3b30"
    public let color: String
    /// An `AnnotationTextSize` raw value.
    public let size: String
    /// Shapes drawn on the picture.
    public let shapes: Int
    /// A PIN is set on the camera computer.
    public let photoEnabled: Bool
    /// A photo taken from the page is shown instead of the live picture.
    public let frozen: Bool
    public let offline: Bool
    public let job: String
    /// The photo browser is open; nil from a camera Mac whose page has none
    /// (an older microCAM), so the viewer shows no Photos button for it.
    public let gallery: Bool?
    /// The open photo browser is a sidebar on the left (big screens), so the
    /// picture and the drawing tools sit beside it.
    public let docked: Bool?
    /// The page hands the shown photo to the viewer (`microcam.download`);
    /// nil from an older camera Mac.
    public let download: Bool?
    /// Space shows the photo on its own: the viewer's window goes full screen.
    public let full: Bool?

    public static func decode(_ json: String) -> StreamPageState? {
        json.data(using: .utf8).flatMap { try? JSONDecoder().decode(StreamPageState.self, from: $0) }
    }
}
