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

    public static func decode(_ json: String) -> StreamPageState? {
        json.data(using: .utf8).flatMap { try? JSONDecoder().decode(StreamPageState.self, from: $0) }
    }
}
