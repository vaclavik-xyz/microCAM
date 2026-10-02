import Foundation

/// Decides, for one viewer of the H.264 stream, which frames it gets.
///
/// A frame only decodes after the keyframe it builds on, so a viewer can't
/// simply skip frames the way the JPEG stream does. A viewer starts at a
/// keyframe; when it falls behind (too many frames still on their way), it
/// drops everything up to the next keyframe and asks for one, so the picture
/// jumps back to now instead of lagging further and further behind.
public struct VideoFeedGate: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case send
        case skip
        /// Skip, and ask the encoder for a keyframe so the viewer can resume.
        case skipAndRequestKeyframe
    }

    /// Frames handed to the network but not sent yet; at 30 fps, 4 frames is ~130 ms behind.
    public static let maxInFlight = 4

    public private(set) var synced = false
    public private(set) var inFlight = 0

    public init() {}

    public mutating func admit(isKeyframe: Bool) -> Decision {
        if synced, inFlight >= Self.maxInFlight {
            synced = false
            return .skipAndRequestKeyframe
        }
        if !synced {
            guard isKeyframe else { return .skip }
            // Still catching up: this keyframe would queue behind old frames.
            guard inFlight == 0 else { return .skipAndRequestKeyframe }
            synced = true
        }
        inFlight += 1
        return .send
    }

    /// A frame admitted with `.send` has left.
    public mutating func sent() {
        inFlight = max(0, inFlight - 1)
    }
}
