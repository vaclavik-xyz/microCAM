import CoreImage
import CoreImage.CIFilterBuiltins

public enum AdjustmentPipeline {
    /// Returns `image` itself when adjustments are neutral, so callers can
    /// skip rendering entirely. Filters with neutral parameters are skipped.
    public static func apply(_ adjustments: ImageAdjustments, to image: CIImage) -> CIImage {
        let a = adjustments.clamped()
        if a.isNeutral { return image }
        var out = image

        if a.brightness != 0 || a.contrast != 1 || a.saturation != 1 {
            let f = CIFilter.colorControls()
            f.inputImage = out
            f.brightness = Float(a.brightness)
            f.contrast = Float(a.contrast)
            f.saturation = Float(a.saturation)
            out = f.outputImage ?? out
        }
        if a.temperature != 6500 || a.tint != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = out
            f.neutral = CIVector(x: a.temperature, y: a.tint)
            f.targetNeutral = CIVector(x: 6500, y: 0)
            out = f.outputImage ?? out
        }
        if a.gamma != 1 {
            let f = CIFilter.gammaAdjust()
            f.inputImage = out
            f.power = Float(1 / a.gamma)
            out = f.outputImage ?? out
        }
        if a.sharpness > 0 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = out
            f.sharpness = Float(a.sharpness)
            out = f.outputImage ?? out
        }
        return out.cropped(to: image.extent)
    }
}
