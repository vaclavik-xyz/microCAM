import AVFoundation

public enum VideoEncoding {
    /// Bits per pixel per frame. HEVC standard at 1080p60 ≈ 6.2 Mbit/s (~2.8 GB/h).
    private static func bitsPerPixel(_ codec: VideoCodec, _ quality: VideoQuality) -> Double {
        switch (codec, quality) {
        case (.hevc, .standard): 0.05
        case (.hevc, .high): 0.10
        case (.h264, .standard): 0.08
        case (.h264, .high): 0.16
        }
    }

    public static func bitrate(codec: VideoCodec, quality: VideoQuality, width: Int, height: Int, fps: Double) -> Int {
        max(2_000_000, Int(Double(width * height) * fps * bitsPerPixel(codec, quality)))
    }

    public static func videoSettings(codec: VideoCodec, quality: VideoQuality,
                                     width: Int, height: Int, fps: Double) -> [String: Any] {
        [
            AVVideoCodecKey: codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate(codec: codec, quality: quality, width: width, height: height, fps: fps),
                AVVideoExpectedSourceFrameRateKey: Int(fps.rounded()),
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
                AVVideoAllowFrameReorderingKey: false,
            ] as [String: Any],
        ]
    }

    /// Mono AAC is plenty for narration.
    public static let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 96_000,
    ]
}
