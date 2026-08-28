import CoreImage
import PhotoCuration
import Vision

struct VisionAnalysis {
    var faceCount: Int
    var faceSignatures: [String]
    var sceneLabels: [SceneLabel]
    var textCoverage: Double
    var sharpness: Double
    var aestheticScore: Double
}

/// Wraps the Vision requests used to decide whether a photo is worth resurfacing.
struct VisionAnalyzer {
    private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    func analyze(_ image: CGImage) -> VisionAnalysis {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let faces = VNDetectFaceRectanglesRequest()
        let scenes = VNClassifyImageRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .fast

        try? handler.perform([faces, scenes, text])

        let faceObservations = faces.results ?? []
        let sceneLabels = (scenes.results ?? [])
            .filter { $0.confidence >= 0.3 }
            .prefix(8)
            .map { SceneLabel(identifier: $0.identifier, confidence: Double($0.confidence)) }

        return VisionAnalysis(
            faceCount: faceObservations.count,
            faceSignatures: faceObservations.map(Self.faceSignature),
            sceneLabels: Array(sceneLabels),
            textCoverage: Self.textCoverage(text.results ?? []),
            sharpness: sharpness(of: image),
            aestheticScore: Self.aestheticScore(scenes: scenes.results ?? [])
        )
    }

    /// Stable per-photo face key. Real person identity comes from the Photos "People"
    /// album on device; this approximation keeps faces distinguishable within a batch.
    private static func faceSignature(_ face: VNFaceObservation) -> String {
        let box = face.boundingBox
        return String(
            format: "face-%.2f-%.2f-%.2f",
            box.midX, box.midY, box.width
        )
    }

    private static func textCoverage(_ observations: [VNRecognizedTextObservation]) -> Double {
        observations.reduce(0) { $0 + Double($1.boundingBox.width * $1.boundingBox.height) }
    }

    /// Variance of the Laplacian, normalised — the standard cheap blur detector.
    private func sharpness(of image: CGImage) -> Double {
        let input = CIImage(cgImage: image)
        guard let edges = CIFilter(
            name: "CIConvolution3X3",
            parameters: [
                kCIInputImageKey: input,
                "inputWeights": CIVector(values: [0, 1, 0, 1, -4, 1, 0, 1, 0], count: 9),
                "inputBias": 0
            ]
        )?.outputImage else { return 1 }

        // Squaring the edge response before averaging approximates the variance of the
        // Laplacian, which is high for sharp images and near zero for blurry ones.
        let squared = edges.applyingFilter(
            "CIMultiplyCompositing",
            parameters: [kCIInputBackgroundImageKey: edges]
        )
        guard let stats = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: squared,
                kCIInputExtentKey: CIVector(cgRect: edges.extent)
            ]
        )?.outputImage else { return 1 }

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            stats,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        let meanSquaredEdge = Double(max(pixel[0], max(pixel[1], pixel[2]))) / 255
        return min(1, meanSquaredEdge * 6)
    }

    /// Vision's aesthetics request exists only on newer OS versions; the scene
    /// confidence of the strongest non-"document" label is a reasonable stand-in.
    private static func aestheticScore(scenes: [VNClassificationObservation]) -> Double {
        let best = scenes
            .filter { !$0.identifier.contains("document") && !$0.identifier.contains("text") }
            .max { $0.confidence < $1.confidence }
        return Double(best?.confidence ?? 0.5)
    }
}
