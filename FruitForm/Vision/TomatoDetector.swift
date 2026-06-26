import Vision
import CoreML
import CoreGraphics
import Accelerate
import os

/// One tomato instance from the segmentation model.
/// `rect` and `mask` are both in **image-normalized** space (top-left origin,
/// [0,1] over width/height) — already un-letterboxed, so downstream code never
/// has to think about the model's 640×640 padded canvas.
struct TomatoInstance {
    let rect: CGRect
    let confidence: Float
    let mask: [[Bool]]   // 160×160 over the image; empty when masks weren't requested
}

/// Decodes YOLOv8-seg Core ML output (raw multiarrays) into per-fruit instances.
final class TomatoDetector {
    private static let log = Logger(subsystem: "com.fruitform.app", category: "TomatoDetector")
    private let vnModel: VNCoreMLModel?
    var confidenceThreshold: Float = 0.50
    var iouThreshold: Float = 0.45

    private let inputSize: Float = 640      // model input is 640×640
    private let maskGrid = 160              // prototype resolution (640/4)
    private let numProposals = 8400
    private let numCoeffs = 32

    init() {
        var loaded: VNCoreMLModel?
        if let url = Bundle.main.url(forResource: "TomatoSegmenter", withExtension: "mlmodelc"),
           let model = try? MLModel(contentsOf: url) {
            loaded = try? VNCoreMLModel(for: model)
        }
        vnModel = loaded
    }

    var isReady: Bool { vnModel != nil }

    /// `computeMasks: false` skips per-fruit mask decoding entirely — use it for
    /// the live preview, which only draws boxes (big perf win on dense piles).
    func detect(cgImage: CGImage, computeMasks: Bool = true) -> [TomatoInstance] {
        guard let vnModel = vnModel else { return [] }

        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFit        // letterbox (aspect-preserving)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return [] }

        guard let results = request.results as? [VNCoreMLFeatureValueObservation] else { return [] }

        // Select the two outputs by tensor shape rather than export name: the
        // detection grid is rank-3 ([1, 37, 8400]); the mask prototypes are
        // rank-4 ([1, 32, 160, 160]). Re-exporting the model renames the
        // tensors (var_1010 / var_1048) but never changes their dimensionality,
        // so matching on rank survives a re-export that hardcoded names wouldn't.
        var detArr: MLMultiArray?     // [1, 37, 8400]  boxes + class + 32 mask coeffs
        var protoArr: MLMultiArray?   // [1, 32, 160, 160] mask prototypes
        for res in results {
            guard let arr = res.featureValue.multiArrayValue else { continue }
            switch arr.shape.count {
            case 3: detArr = arr
            case 4: protoArr = arr
            default: break
            }
        }
        guard let det = detArr, let proto = protoArr else {
            Self.log.error("Detector outputs not identifiable by shape (expected a rank-3 detection grid and a rank-4 prototype tensor); returning no detections.")
            return []
        }

        // The image is letterboxed into the 640² canvas — these params undo it.
        let lb = Letterbox(imageW: cgImage.width, imageH: cgImage.height)
        let n = numProposals
        let detPtr = det.dataPointer.bindMemory(to: Float.self, capacity: 37 * n)

        // 1) Parse proposals above threshold; un-letterbox boxes to image space.
        struct Cand { var rect: CGRect; var conf: Float; var coeffs: [Float] }
        var cands: [Cand] = []
        for i in 0..<n {
            let conf = detPtr[4 * n + i]
            if conf < confidenceThreshold { continue }
            let cx = detPtr[i], cy = detPtr[n + i], w = detPtr[2 * n + i], h = detPtr[3 * n + i]
            let mnx = (cx - w / 2) / inputSize, mny = (cy - h / 2) / inputSize
            let (ix0, iy0) = lb.toImage(Double(mnx), Double(mny))
            let (ix1, iy1) = lb.toImage(Double(mnx + w / inputSize), Double(mny + h / inputSize))
            let rect = CGRect(x: ix0, y: iy0, width: ix1 - ix0, height: iy1 - iy0).clampedToUnit()
            guard rect.width > 0, rect.height > 0 else { continue }
            var coeffs = [Float](repeating: 0, count: numCoeffs)
            for j in 0..<numCoeffs { coeffs[j] = detPtr[(5 + j) * n + i] }
            cands.append(Cand(rect: rect, conf: conf, coeffs: coeffs))
        }
        cands.sort { $0.conf > $1.conf }

        // 2) NMS (boxes only — cheap).
        var keep: [Int] = []
        var active = [Bool](repeating: true, count: cands.count)
        for i in 0..<cands.count where active[i] {
            keep.append(i)
            for j in (i + 1)..<cands.count where active[j] {
                if iou(cands[i].rect, cands[j].rect) > iouThreshold { active[j] = false }
            }
        }

        // 3) Masks for the survivors (only if requested).
        let protoPtr = proto.dataPointer.bindMemory(to: Float.self, capacity: numCoeffs * maskGrid * maskGrid)
        return keep.map { idx in
            let c = cands[idx]
            let mask = computeMasks ? buildMask(coeffs: c.coeffs, protoPtr: protoPtr, rect: c.rect, lb: lb) : []
            return TomatoInstance(rect: c.rect, confidence: c.conf, mask: mask)
        }
    }

    /// mask = (prototypes · coeffs) thresholded. Because we threshold the sigmoid
    /// at 0.5, that's identical to thresholding the raw logit at 0 — so no exp()
    /// needed. The 32×25600 combine is a single BLAS GEMV.
    private func buildMask(coeffs: [Float], protoPtr: UnsafePointer<Float>,
                           rect: CGRect, lb: Letterbox) -> [[Bool]] {
        let px = maskGrid * maskGrid
        var logits = [Float](repeating: 0, count: px)
        coeffs.withUnsafeBufferPointer { c in
            logits.withUnsafeMutableBufferPointer { out in
                // y = Aᵀ·x ; A = proto [32 × 25600] row-major, x = coeffs[32], y = [25600]
                cblas_sgemv(CblasRowMajor, CblasTrans,
                            Int32(numCoeffs), Int32(px), 1.0,
                            protoPtr, Int32(px),
                            c.baseAddress, 1, 0.0,
                            out.baseAddress, 1)
            }
        }

        // Resample the model-space logits onto an image-space 160×160 grid,
        // clipped to the (image-space) bounding box.
        var result = [[Bool]](repeating: [Bool](repeating: false, count: maskGrid), count: maskGrid)
        for iy in 0..<maskGrid {
            let inY = (Double(iy) + 0.5) / Double(maskGrid)
            for ix in 0..<maskGrid {
                let inX = (Double(ix) + 0.5) / Double(maskGrid)
                if !rect.contains(CGPoint(x: inX, y: inY)) { continue }
                let (mnx, mny) = lb.toModel(inX, inY)
                let gx = min(maskGrid - 1, max(0, Int(mnx * Double(maskGrid))))
                let gy = min(maskGrid - 1, max(0, Int(mny * Double(maskGrid))))
                if logits[gy * maskGrid + gx] > 0 { result[iy][ix] = true }
            }
        }
        return result
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let inter = a.intersection(b)
        if inter.isNull { return 0 }
        let i = Float(inter.width * inter.height)
        let u = Float(a.width * a.height + b.width * b.height) - i
        return u > 0 ? i / u : 0
    }
}

/// Maps between the model's letterboxed 640² canvas (aspect-preserving, centered
/// padding) and image-normalized [0,1] coordinates.
struct Letterbox {
    let scaledW: Double, scaledH: Double, padX: Double, padY: Double
    init(imageW: Int, imageH: Int) {
        let w = Double(imageW), h = Double(imageH)
        if w >= h { scaledW = 1.0; scaledH = h / w } else { scaledH = 1.0; scaledW = w / h }
        padX = (1.0 - scaledW) / 2.0
        padY = (1.0 - scaledH) / 2.0
    }
    /// model-normalized [0,1] → image-normalized [0,1]
    func toImage(_ mx: Double, _ my: Double) -> (CGFloat, CGFloat) {
        (CGFloat((mx - padX) / scaledW), CGFloat((my - padY) / scaledH))
    }
    /// image-normalized [0,1] → model-normalized [0,1]
    func toModel(_ ix: Double, _ iy: Double) -> (Double, Double) {
        (padX + ix * scaledW, padY + iy * scaledH)
    }
}

private extension CGRect {
    func clampedToUnit() -> CGRect {
        let x0 = min(max(minX, 0), 1), y0 = min(max(minY, 0), 1)
        let x1 = min(max(maxX, 0), 1), y1 = min(max(maxY, 0), 1)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
