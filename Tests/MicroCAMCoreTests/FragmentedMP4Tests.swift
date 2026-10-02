import AVFoundation
import VideoToolbox
import XCTest
@testable import MicroCAMCore

final class FragmentedMP4Tests: XCTestCase {
    func testCodecStringFromAvcC() {
        XCTAssertEqual(FragmentedMP4.codec(avcC: Data([1, 0x64, 0x00, 0x28, 0xFF])), "avc1.640028")
        XCTAssertNil(FragmentedMP4.codec(avcC: Data([0, 0x64, 0x00, 0x28])))
        XCTAssertNil(FragmentedMP4.codec(avcC: Data([1, 0x64])))
    }

    /// The data offset points just past the `mdat` header, where the sample starts.
    func testFragmentLayout() {
        let sample = Data([0, 0, 0, 2, 0x65, 0x88])
        let fragment = FragmentedMP4.fragment(sequence: 7, decodeTime: 1_000_000, duration: 3000,
                                              sample: sample, isKeyframe: true)
        let moofSize = Int(fragment.prefix(4).reduce(0) { $0 << 8 | UInt32($1) })
        XCTAssertEqual(String(decoding: fragment[4..<8], as: UTF8.self), "moof")
        XCTAssertEqual(String(decoding: fragment[moofSize + 4..<moofSize + 8], as: UTF8.self), "mdat")
        XCTAssertEqual(fragment.suffix(sample.count), sample)
        XCTAssertEqual(fragment.count, moofSize + 8 + sample.count)
    }

    /// Real H.264 from VideoToolbox, muxed as a live stream, must read back as
    /// a playable movie with every frame decodable.
    func testEncodedStreamPlaysBack() async throws {
        let width = 320, height = 240, frames = 30
        let encoded = try encode(width: width, height: height, frames: frames)
        let avcC = try XCTUnwrap(encoded.avcC)
        XCTAssertNotNil(FragmentedMP4.codec(avcC: avcC))
        XCTAssertTrue(encoded.samples[0].key)

        var stream = FragmentedMP4.initSegment(width: width, height: height, avcC: avcC)
        var time: UInt64 = 0
        for (i, sample) in encoded.samples.enumerated() {
            stream += FragmentedMP4.fragment(sequence: UInt32(i + 1), decodeTime: time, duration: 3000,
                                             sample: sample.data, isKeyframe: sample.key)
            time += 3000
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fmp4-\(UUID()).mp4")
        try stream.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: width, height: height))
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, Double(frames) / 30, accuracy: 0.01)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var decoded = 0
        while let buffer = output.copyNextSampleBuffer() {
            if CMSampleBufferGetImageBuffer(buffer) != nil { decoded += 1 }
        }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertEqual(decoded, frames)
    }

    // MARK: Encoding

    private struct Encoded {
        var avcC: Data?
        var samples: [(data: Data, key: Bool)] = []
    }

    private func encode(width: Int, height: Int, frames: Int) throws -> Encoded {
        var session: VTCompressionSession?
        XCTAssertEqual(VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height),
                                                  codecType: kCMVideoCodecType_H264, encoderSpecification: nil,
                                                  imageBufferAttributes: nil, compressedDataAllocator: nil,
                                                  outputCallback: nil, refcon: nil, compressionSessionOut: &session), noErr)
        let compression = try XCTUnwrap(session)
        VTSessionSetProperty(compression, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(compression, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(compression, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 10 as CFNumber)

        let result = LockedValue(Encoded())
        for i in 0..<frames {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            let buffer = try XCTUnwrap(pixelBuffer)
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(i * 8 % 255), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            VTCompressionSessionEncodeFrame(compression, imageBuffer: buffer,
                                            presentationTimeStamp: CMTime(value: CMTimeValue(i), timescale: 30),
                                            duration: CMTime(value: 1, timescale: 30), frameProperties: nil,
                                            infoFlagsOut: nil) { status, _, sample in
                guard status == noErr, let sample, let frame = EncodedFrame(sample) else { return }
                result.update { encoded in
                    if encoded.avcC == nil { encoded.avcC = frame.avcC }
                    encoded.samples.append((frame.data, frame.isKeyframe))
                }
            }
        }
        VTCompressionSessionCompleteFrames(compression, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(compression)
        XCTAssertEqual(result.value.samples.count, frames)
        return result.value
    }

}
