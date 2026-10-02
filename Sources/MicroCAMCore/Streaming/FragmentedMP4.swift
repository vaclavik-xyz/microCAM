import Foundation

/// A live H.264 stream as fragmented MP4: one init segment (`ftyp` + `moov`),
/// then one `moof` + `mdat` per frame. Browsers play it with Media Source
/// Extensions (`ManagedMediaSource` on iPhone), which, unlike WebCodecs, also
/// work on a plain-HTTP page.
///
/// Samples are AVCC (4-byte NAL lengths), exactly as VideoToolbox emits them;
/// `avcC` is the decoder configuration record from the format description.
public enum FragmentedMP4 {
    /// Ticks per second of the video track.
    public static let timescale: UInt32 = 90_000

    public static func initSegment(width: Int, height: Int, avcC: Data) -> Data {
        let brands = join(Data("iso5".utf8), u32(512), Data("iso5iso6avc1mp41".utf8))
        let trex = fullBox("trex", join(u32(1), u32(1), u32(0), u32(0), u32(0)))
        return join(box("ftyp", brands),
                    box("moov", join(movieHeader(), track(width: width, height: height, avcC: avcC), box("mvex", trex))))
    }

    /// One frame. `decodeTime` and `duration` are in `timescale` ticks; the
    /// decode time of a frame is the previous frame's decode time plus its duration.
    public static func fragment(sequence: UInt32, decodeTime: UInt64, duration: UInt32,
                                sample: Data, isKeyframe: Bool) -> Data {
        // trun: data offset, then per sample duration, size and flags.
        let flags: UInt32 = isKeyframe ? 0x0200_0000 : 0x0101_0000
        func moof(dataOffset: UInt32) -> Data {
            let run = fullBox("trun", join(u32(1), u32(dataOffset), u32(duration), u32(UInt32(sample.count)), u32(flags)),
                              flags: 0x000701)
            let header = fullBox("tfhd", u32(1), flags: 0x02_0000)   // default-base-is-moof
            let time = fullBox("tfdt", u64(decodeTime), version: 1)
            return box("moof", join(fullBox("mfhd", u32(sequence)), box("traf", join(header, time, run))))
        }
        let size = moof(dataOffset: 0).count
        return join(moof(dataOffset: UInt32(size + 8)), box("mdat", sample))
    }

    /// The RFC 6381 codec string for `MediaSource.isTypeSupported` and `addSourceBuffer`,
    /// e.g. `avc1.640028`, read from the profile and level in `avcC`.
    public static func codec(avcC: Data) -> String? {
        let bytes = [UInt8](avcC)
        guard bytes.count >= 4, bytes[0] == 1 else { return nil }
        return "avc1." + bytes[1...3].map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Boxes

    private static func movieHeader() -> Data {
        fullBox("mvhd", join(u32(0), u32(0), u32(1000), u32(0),         // times, timescale, duration
                             u32(0x0001_0000), u16(0x0100), Data(count: 10), // rate, volume, reserved
                             matrix(), Data(count: 24), u32(2)))             // pre-defined, next track
    }

    private static func track(width: Int, height: Int, avcC: Data) -> Data {
        let header = fullBox("tkhd", join(u32(0), u32(0), u32(1), u32(0), u32(0),  // times, track 1, reserved, duration
                                          Data(count: 8), u16(0), u16(0), u16(0), u16(0), // reserved, layer, group, volume, reserved
                                          matrix(), u32(UInt32(width) << 16), u32(UInt32(height) << 16)),
                             flags: 3)
        let mediaHeader = fullBox("mdhd", join(u32(0), u32(0), u32(timescale), u32(0), u16(0x55C4), u16(0))) // "und"
        let handler = fullBox("hdlr", join(u32(0), Data("vide".utf8), Data(count: 12), Data("VideoHandler\0".utf8)))
        let entry = box("avc1", join(Data(count: 6), u16(1),                        // reserved, data reference
                                     Data(count: 16), u16(UInt16(width)), u16(UInt16(height)),
                                     u32(0x0048_0000), u32(0x0048_0000), u32(0),     // 72 dpi, reserved
                                     u16(1), Data(count: 32), u16(0x0018), u16(0xFFFF), // frames, compressor, depth
                                     box("avcC", avcC)))
        let table = box("stbl", join(fullBox("stsd", join(u32(1), entry)),
                                     fullBox("stts", u32(0)), fullBox("stsc", u32(0)),
                                     fullBox("stsz", join(u32(0), u32(0))), fullBox("stco", u32(0))))
        let info = box("minf", join(fullBox("vmhd", join(u16(0), Data(count: 6)), flags: 1),
                                    box("dinf", fullBox("dref", join(u32(1), fullBox("url ", Data(), flags: 1)))),
                                    table))
        return box("trak", join(header, box("mdia", join(mediaHeader, handler, info))))
    }

    private static func matrix() -> Data {
        join(u32(0x0001_0000), u32(0), u32(0), u32(0), u32(0x0001_0000), u32(0), u32(0), u32(0), u32(0x4000_0000))
    }

    static func box(_ type: String, _ payload: Data) -> Data {
        join(u32(UInt32(8 + payload.count)), Data(type.utf8), payload)
    }

    static func fullBox(_ type: String, _ payload: Data, version: UInt8 = 0, flags: UInt32 = 0) -> Data {
        box(type, join(u32(UInt32(version) << 24 | flags), payload))
    }

    private static func join(_ parts: Data...) -> Data {
        var data = Data(capacity: parts.reduce(0) { $0 + $1.count })
        parts.forEach { data.append($0) }
        return data
    }

    private static func u16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
    private static func u32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
    private static func u64(_ value: UInt64) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
}
