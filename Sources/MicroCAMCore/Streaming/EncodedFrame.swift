import CoreMedia

/// One H.264 frame from VideoToolbox, ready for `FragmentedMP4`.
public struct EncodedFrame: Sendable {
    /// AVCC: NAL units with 4-byte lengths.
    public var data: Data
    public var isKeyframe: Bool
    /// The decoder configuration record (SPS and PPS).
    public var avcC: Data
    public var width: Int
    public var height: Int

    public init(data: Data, isKeyframe: Bool, avcC: Data, width: Int, height: Int) {
        self.data = data; self.isKeyframe = isKeyframe; self.avcC = avcC; self.width = width; self.height = height
    }

    /// Nil for a dropped frame or one without an `avcC` (not H.264).
    public init?(_ sample: CMSampleBuffer) {
        guard let block = CMSampleBufferGetDataBuffer(sample),
              let format = CMSampleBufferGetFormatDescription(sample),
              let atoms = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any],
              let avcC = atoms["avcC"] as? Data else { return nil }
        let length = CMBlockBufferGetDataLength(block)
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
        guard status == kCMBlockBufferNoErr else { return nil }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        self.init(data: data, isKeyframe: !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false),
                  avcC: avcC, width: Int(dimensions.width), height: Int(dimensions.height))
    }
}
