import UIKit

struct CaptureDraft {
    let frame: CapturedFrame
    let accession: String
    let mode: CaptureMode
    let sessionID: UUID
    let timestamp: Date
    var measurements: [FruitMeasurement]
    let instances: [TomatoInstance]
}

/// Orchestrates one capture: find each fruit, measure it, and (when configured)
/// refine shape with the cloud vision model. Uses the trained model when bundled,
/// otherwise the color detector.
final class CaptureProcessor {
    private let detector = TomatoDetector()
    private let shapeClassifier = TomatoShapeClassifier()
    private let ratingClassifier = TomatoRatingClassifier()

    func process(frame: CapturedFrame,
                 accession: String,
                 mode: CaptureMode,
                 sessionID: UUID,
                 timestamp: Date,
                 settings: AppSettings) async -> CaptureDraft {

        // No trained model = no trustworthy measurement. Return nothing (NA)
        // rather than fall back to an untrustworthy color guess.
        guard detector.isReady else {
            return CaptureDraft(frame: frame, accession: accession, mode: mode,
                                sessionID: sessionID, timestamp: timestamp,
                                measurements: [], instances: [])
        }

        let cloud: ClaudeClient? = settings.cloudReady
            ? ClaudeClient(apiKey: settings.apiKey, model: settings.model)
            : nil
        return await processWithModel(frame: frame, accession: accession, mode: mode,
                                      sessionID: sessionID, timestamp: timestamp, cloud: cloud)
    }

    // MARK: - Trained-model path (boxes, any color, touching separated)

    private func processWithModel(frame: CapturedFrame, accession: String, mode: CaptureMode,
                                  sessionID: UUID, timestamp: Date, cloud: ClaudeClient?) async -> CaptureDraft {
        var results: [FruitMeasurement] = []
        let instances = detector.detect(cgImage: frame.cgImage)
        
        let width = Int(frame.imageWidth)
        let height = Int(frame.imageHeight)
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let context = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.draw(frame.cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        
        for instance in instances {
            let m = BoxMeasurement.measure(rect: instance.rect, frame: frame)
            // Mask-based morphometrics (true silhouette); fall back to the box estimate.
            let morph = instance.mask.isEmpty
                ? nil
                : MorphometricsAnalyzer.analyze(mask: instance.mask, frame: frame, depthM: m.depthMeters)

            var measurement = FruitMeasurement(
                accession: accession, captureMode: mode, timestamp: timestamp, sessionID: sessionID,
                majorAxisCm: morph?.majorAxisCm ?? m.majorAxisCm,
                minorAxisCm: morph?.minorAxisCm ?? m.minorAxisCm,
                depthMeters: m.depthMeters,
                shapeIndex: morph?.shapeIndex ?? m.shapeIndex, eccentricity: morph?.eccentricity,
                solidity: morph?.solidity,
                shapeCategory: morph?.shapeCategory ?? coarseShape(m.shapeIndex), classifierConfidence: nil,
                note: nil, occluded: m.occluded, source: "device")

            if let vol = FruitGeometry3D.estimate(instance: instance, frame: frame) {
                measurement.volumeCm3 = vol.volumeCm3
                measurement.weightGramsEst = vol.weightGrams()
                measurement.semiAxisACm = vol.semiAxisACm
                measurement.semiAxisBCm = vol.semiAxisBCm
                measurement.semiAxisCCm = vol.semiAxisCCm
            }

            // LiDAR 3D form: recovers flatness the silhouette can't see, and
            // upgrades a round-ish-but-flat fruit to "flat" (e.g. oblate beefsteak).
            let form = FruitFormAnalyzer.analyze(instance: instance, frame: frame,
                                                 shapeIndex: morph?.shapeIndex ?? m.shapeIndex)
            measurement.flatness = form?.flatness
            if let flatCat = form?.formCategory { measurement.shapeCategory = flatCat }

            // Shape category precedence: trained on-device model (best) → cloud
            // (if enabled and no model) → flatness/heuristic already set above.
            if shapeClassifier.isReady, !m.occluded,
               let cg = cropCGImage(frame: frame, normRect: instance.rect),
               let cls = shapeClassifier.classify(cgImage: cg), cls.confidence >= 0.50 {
                measurement.shapeCategory = cls.label
                measurement.classifierConfidence = cls.confidence
                measurement.source = "device+model"
            } else if let cloud = cloud, !m.occluded, let jpeg = crop(frame: frame, normRect: instance.rect) {
                if let cls = try? await cloud.classify(jpeg: jpeg, shapeIndex: m.shapeIndex,
                                                       solidity: morph?.solidity, flatness: form?.flatness) {
                    measurement.shapeCategory = cls.category
                    measurement.classifierConfidence = cls.confidence
                    measurement.note = cls.note
                    measurement.source = "device+cloud"
                }
            }

            // fruit_shape_rating trait: 1–9 processing desirability, predicted by
            // the trained rating model on the same crop (independent of shape class).
            if ratingClassifier.isReady, !m.occluded,
               let cg = cropCGImage(frame: frame, normRect: instance.rect),
               let r = ratingClassifier.classify(cgImage: cg) {
                measurement.shapeRating = r.rating
                measurement.shapeRatingConfidence = r.confidence
            }

            // Extract Color from Mask
            var sumR = 0, sumG = 0, sumB = 0, count = 0
            for my in 0..<160 {
                for mx in 0..<160 {
                    if instance.mask[my][mx] {
                        let px = Int(CGFloat(mx) / 160.0 * frame.imageWidth)
                        let py = Int(CGFloat(my) / 160.0 * frame.imageHeight)
                        if px >= 0 && px < width && py >= 0 && py < height {
                            let offset = (py * width + px) * 4
                            sumR += Int(rawData[offset])
                            sumG += Int(rawData[offset + 1])
                            sumB += Int(rawData[offset + 2])
                            count += 1
                        }
                    }
                }
            }

            if count > 0 {
                let r = sumR / count
                let g = sumG / count
                let b = sumB / count
                measurement.colorHex = String(format: "#%02X%02X%02X", r, g, b)
                
                // RGB to Hue
                let rf = Float(r) / 255.0
                let gf = Float(g) / 255.0
                let bf = Float(b) / 255.0
                let maxC = max(rf, max(gf, bf))
                let minC = min(rf, min(gf, bf))
                var h: Float = 0
                if maxC != minC {
                    if maxC == rf {
                        h = (60.0 * ((gf - bf) / (maxC - minC)) + 360.0).truncatingRemainder(dividingBy: 360.0)
                    } else if maxC == gf {
                        h = 60.0 * ((bf - rf) / (maxC - minC)) + 120.0
                    } else {
                        h = 60.0 * ((rf - gf) / (maxC - minC)) + 240.0
                    }
                }
                
                measurement.ripeness = (h < 45 || h > 315) ? "Red" : "Green"
            }
            
            results.append(measurement)
        }
        
        return CaptureDraft(frame: frame, accession: accession, mode: mode, sessionID: sessionID, timestamp: timestamp, measurements: results, instances: instances)
    }

    // MARK: - Helpers

    private func coarseShape(_ shapeIndex: Double?) -> String {
        guard let si = shapeIndex else { return "tomato" }
        if si < 1.15 { return "round" }
        if si < 1.40 { return "oval" }
        return "elongated"
    }

    /// Padded fruit crop as a CGImage (for the on-device classifier).
    /// Pad is a fraction of the BOX (matching ml/extract_crops.py), NOT the image —
    /// padding by the image size buries small fruit in background and the classifier
    /// mis-reads them as flat/fasciated.
    private func cropCGImage(frame: CapturedFrame, normRect: CGRect) -> CGImage? {
        let rect = paddedPixelRect(normRect, frame: frame)
        guard !rect.isNull, rect.width > 1, rect.height > 1 else { return nil }
        return frame.cgImage.cropping(to: rect)
    }

    /// Crop from a standard-normalized rect (top-left origin).
    private func crop(frame: CapturedFrame, normRect: CGRect) -> Data? {
        let rect = paddedPixelRect(normRect, frame: frame)
        guard !rect.isNull, rect.width > 1, rect.height > 1,
              let cg = frame.cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.85)
    }

    /// Box+pad crop in pixel space. `pad` is a fraction of the box, clipped to image.
    private func paddedPixelRect(_ normRect: CGRect, frame: CapturedFrame, pad: CGFloat = 0.06) -> CGRect {
        let padX = normRect.width * pad, padY = normRect.height * pad
        return CGRect(
            x: (normRect.minX - padX) * frame.imageWidth,
            y: (normRect.minY - padY) * frame.imageHeight,
            width: (normRect.width + 2 * padX) * frame.imageWidth,
            height: (normRect.height + 2 * padY) * frame.imageHeight
        ).intersection(CGRect(x: 0, y: 0, width: frame.imageWidth, height: frame.imageHeight))
    }
}
