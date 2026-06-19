import Vision
import CoreML
import CoreGraphics

/// On-device shape-RATING model (the `fruit_shape_rating` trait): runs on a single
/// fruit crop and returns a 1–9 processing-tomato desirability score. Trained on
/// the rating-mode captures; the class labels are the integer ratings that have
/// data (currently the odd anchors 1/3/5/7/9). No-ops gracefully if the model
/// isn't bundled yet. Mirrors `TomatoShapeClassifier`.
final class TomatoRatingClassifier {
    private let model: VNCoreMLModel?

    init() {
        if let url = Bundle.main.url(forResource: "TomatoRatingNet", withExtension: "mlmodelc"),
           let m = try? MLModel(contentsOf: url) {
            model = try? VNCoreMLModel(for: m)
        } else {
            model = nil
        }
    }

    var isReady: Bool { model != nil }

    struct Result { let rating: Int; let confidence: Double }

    /// `cgImage` should be a tight-ish crop of one fruit (box + small pad), the
    /// same framing the model trained on. Returns the top rating + its probability.
    func classify(cgImage: CGImage) -> Result? {
        guard let model else { return nil }
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let obs = request.results as? [VNClassificationObservation],
              let top = obs.first,
              let rating = Int(top.identifier) else { return nil }
        return Result(rating: rating, confidence: Double(top.confidence))
    }
}
