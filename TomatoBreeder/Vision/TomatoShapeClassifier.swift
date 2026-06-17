import Vision
import CoreML
import CoreGraphics

/// On-device shape classifier (the trained model that replaces the heuristic +
/// cloud). Runs on a single fruit crop and returns one of the trained classes.
/// No-ops gracefully if the model isn't bundled yet.
final class TomatoShapeClassifier {
    private let model: VNCoreMLModel?

    init() {
        if let url = Bundle.main.url(forResource: "TomatoShapeNet", withExtension: "mlmodelc"),
           let m = try? MLModel(contentsOf: url) {
            model = try? VNCoreMLModel(for: m)
        } else {
            model = nil
        }
    }

    var isReady: Bool { model != nil }

    struct Result { let label: String; let confidence: Double }

    /// `cgImage` should be a tight-ish crop of one fruit (box + small pad), the
    /// same framing the model trained on. Returns the top class + its probability.
    func classify(cgImage: CGImage) -> Result? {
        guard let model else { return nil }
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let obs = request.results as? [VNClassificationObservation], let top = obs.first else { return nil }
        // Trained folder names are upper-case (ROUND…); lower-case for display parity.
        return Result(label: top.identifier.lowercased(), confidence: Double(top.confidence))
    }
}
