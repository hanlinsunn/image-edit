import CoreGraphics
import CoreImage

/// 64-bit difference hash used for near-duplicate detection.
enum PerceptualHash {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func difference(of image: CGImage) -> UInt64 {
        let width = 9
        let height = 8
        guard let grayscale = downsampled(image, width: width, height: height) else { return 0 }

        var hash: UInt64 = 0
        var bit = 0
        for row in 0..<height {
            for column in 0..<(width - 1) {
                let left = grayscale[row * width + column]
                let right = grayscale[row * width + column + 1]
                if left > right { hash |= (1 << UInt64(bit)) }
                bit += 1
            }
        }
        return hash
    }

    private static func downsampled(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}
