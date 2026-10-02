import CoreImage
import MicroCAMCore

/// Latest camera frame → adjustments → JPEG, off the main thread.
final class PhotoCapturer {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let queue = DispatchQueue(label: "microcam.photo", qos: .userInitiated)
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    func capture(_ pixelBuffer: CVPixelBuffer, adjustments: ImageAdjustments, quality: Double,
                 to url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            let image = AdjustmentPipeline.apply(adjustments, to: CIImage(cvPixelBuffer: pixelBuffer))
            let options = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
            let result: Result<URL, Error>
            do {
                try self.context.writeJPEGRepresentation(of: image, to: url, colorSpace: self.colorSpace, options: options)
                result = .success(url)
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// A picture from another device (iPhone, iPad) → JPEG, upright, without adjustments.
    func save(imageData data: Data, quality: Double, to url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            let result: Result<URL, Error>
            if let image = CIImage(data: data, options: [.applyOrientationProperty: true]) {
                let options = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
                do {
                    try self.context.writeJPEGRepresentation(of: image, to: url, colorSpace: self.colorSpace, options: options)
                    result = .success(url)
                } catch {
                    result = .failure(error)
                }
            } else {
                result = .failure(CocoaError(.fileReadCorruptFile))
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
