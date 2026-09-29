import Foundation

/// Software image corrections applied identically to preview, photos and
/// video. Neutral values mean "untouched": the app then uses the zero-copy
/// passthrough path.
public struct ImageAdjustments: Equatable, Sendable {
    public var brightness: Double = 0      // CIColorControls.brightness
    public var contrast: Double = 1        // CIColorControls.contrast
    public var saturation: Double = 1      // CIColorControls.saturation
    public var temperature: Double = 6500  // Kelvin; > 6500 warms
    public var tint: Double = 0            // green (-) … magenta (+)
    public var gamma: Double = 1           // > 1 brightens midtones
    public var sharpness: Double = 0       // CISharpenLuminance.sharpness

    public init() {}

    public static let neutral = ImageAdjustments()
    public var isNeutral: Bool { self == .neutral }

    public static let ranges: [WritableKeyPath<ImageAdjustments, Double>: ClosedRange<Double>] = [
        \.brightness: -0.5...0.5,
        \.contrast: 0.5...2,
        \.saturation: 0...2,
        \.temperature: 3000...10000,
        \.tint: -100...100,
        \.gamma: 0.5...2,
        \.sharpness: 0...2,
    ]

    public func clamped() -> ImageAdjustments {
        var copy = self
        for (path, range) in Self.ranges {
            copy[keyPath: path] = min(max(copy[keyPath: path], range.lowerBound), range.upperBound)
        }
        return copy
    }
}

extension ImageAdjustments: Codable {
    private enum CodingKeys: String, CodingKey {
        case brightness, contrast, saturation, temperature, tint, gamma, sharpness
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ImageAdjustments.neutral
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? d.brightness
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? d.contrast
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? d.saturation
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? d.temperature
        tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? d.tint
        gamma = try c.decodeIfPresent(Double.self, forKey: .gamma) ?? d.gamma
        sharpness = try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? d.sharpness
    }
}
