import UIKit

/// Builds a fruit the auto-detector missed. The user drags a box around it on the
/// saved photo; we segment the fruit from the persisted LiDAR depth (falling back
/// to color when depth is absent) and run the *same* measurement pipeline as an
/// auto-detected fruit, so it lands in the data/CSV identically.
enum ManualFruit {

    static let grid = 160
    private static let classifier = TomatoShapeClassifier()

    /// `rawBox` is normalized in sensor/landscape space (top-left origin, x over
    /// width, y over height) — the same space as the stored masks.
    static func build(rawBox: CGRect,
                      frame: CapturedFrame,
                      accession: String,
                      mode: CaptureMode,
                      sessionID: UUID,
                      timestamp: Date) -> (FruitMeasurement, StoredFruit)? {
        guard let seg = segment(rawBox: rawBox, frame: frame) else { return nil }
        let mask = seg.mask
        let rect = seg.bbox
        let instance = TomatoInstance(rect: rect, confidence: 1.0, mask: mask)

        let m = BoxMeasurement.measure(rect: rect, frame: frame)
        let morph = MorphometricsAnalyzer.analyze(mask: mask, frame: frame, depthM: m.depthMeters)

        var meas = FruitMeasurement(
            accession: accession, captureMode: mode, timestamp: timestamp, sessionID: sessionID,
            majorAxisCm: morph?.majorAxisCm ?? m.majorAxisCm,
            minorAxisCm: morph?.minorAxisCm ?? m.minorAxisCm,
            depthMeters: m.depthMeters,
            shapeIndex: morph?.shapeIndex ?? m.shapeIndex, eccentricity: morph?.eccentricity,
            solidity: morph?.solidity,
            shapeCategory: morph?.shapeCategory ?? coarseShape(m.shapeIndex), classifierConfidence: nil,
            note: "Manually added", occluded: m.occluded, source: "manual")

        if let vol = FruitGeometry3D.estimate(instance: instance, frame: frame) {
            meas.volumeCm3 = vol.volumeCm3
            meas.weightGramsEst = vol.weightGrams()
            meas.semiAxisACm = vol.semiAxisACm
            meas.semiAxisBCm = vol.semiAxisBCm
            meas.semiAxisCCm = vol.semiAxisCCm
        }

        let form = FruitFormAnalyzer.analyze(instance: instance, frame: frame,
                                             shapeIndex: morph?.shapeIndex ?? m.shapeIndex)
        meas.flatness = form?.flatness
        if let flatCat = form?.formCategory { meas.shapeCategory = flatCat }

        if classifier.isReady, let cg = cropCG(frame: frame, normRect: rect),
           let cls = classifier.classify(cgImage: cg), cls.confidence >= 0.50 {
            meas.shapeCategory = cls.label
            meas.classifierConfidence = cls.confidence
            meas.source = "manual+model"
        }

        if let color = meanColor(mask: mask, frame: frame) {
            meas.colorHex = color.hex
            meas.ripeness = color.ripeness
        }

        let stored = StoredFruit(measurementID: meas.id, confidence: 1.0,
                                 rect: [rect.minX, rect.minY, rect.width, rect.height],
                                 maskData: CaptureContext.packMask(mask))
        return (meas, stored)
    }

    /// Padded fruit crop as a CGImage (for the on-device classifier).
    private static func cropCG(frame: CapturedFrame, normRect: CGRect) -> CGImage? {
        let pad = 0.06
        let rect = CGRect(
            x: (normRect.minX - pad) * frame.imageWidth,
            y: (normRect.minY - pad) * frame.imageHeight,
            width: (normRect.width + 2 * pad) * frame.imageWidth,
            height: (normRect.height + 2 * pad) * frame.imageHeight
        ).intersection(CGRect(x: 0, y: 0, width: frame.imageWidth, height: frame.imageHeight))
        guard !rect.isNull, rect.width > 1, rect.height > 1 else { return nil }
        return frame.cgImage.cropping(to: rect)
    }

    // MARK: - Segmentation

    /// Depth-coherent blob inside the box, grown from the center and hole-filled.
    /// Returns the 160×160 image-space mask and its tight normalized bounding box.
    private static func segment(rawBox: CGRect, frame: CapturedFrame) -> (mask: [[Bool]], bbox: CGRect)? {
        let box = rawBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard box.width > 0.01, box.height > 0.01 else { return nil }

        let gx0 = max(0, Int(box.minX * Double(grid)))
        let gx1 = min(grid - 1, Int((box.maxX * Double(grid)).rounded(.up)))
        let gy0 = max(0, Int(box.minY * Double(grid)))
        let gy1 = min(grid - 1, Int((box.maxY * Double(grid)).rounded(.up)))
        guard gx1 > gx0, gy1 > gy0 else { return nil }

        // Reference depth from the central fifth of the box.
        let center = CGRect(x: box.midX - box.width * 0.2, y: box.midY - box.height * 0.2,
                            width: box.width * 0.4, height: box.height * 0.4)
        let d0 = frame.depth?.medianDepth(imageRect: center).map(Double.init)
        let band = 0.04   // meters — half a typical processing tomato

        // Color buffer (only needed when depth is unavailable).
        let rgba = (d0 == nil) ? rgbaBuffer(frame: frame) : nil

        var cand = [[Bool]](repeating: [Bool](repeating: false, count: grid), count: grid)
        for gy in gy0...gy1 {
            for gx in gx0...gx1 {
                let normX = (Double(gx) + 0.5) / Double(grid)
                let normY = (Double(gy) + 0.5) / Double(grid)
                if let d0, let depth = frame.depth, depth.width > 0, depth.height > 0 {
                    let dx = min(depth.width - 1, max(0, Int(normX * Double(depth.width))))
                    let dy = min(depth.height - 1, max(0, Int(normY * Double(depth.height))))
                    let z = Double(depth.values[dy * depth.width + dx])
                    if z.isFinite, z > 0, abs(z - d0) <= band { cand[gy][gx] = true }
                } else if let rgba {
                    if isSaturated(rgba: rgba, normX: normX, normY: normY, frame: frame) { cand[gy][gx] = true }
                }
            }
        }

        // Keep only the blob connected to the box center (drops stray background).
        let cgx = min(grid - 1, max(0, Int(box.midX * Double(grid))))
        let cgy = min(grid - 1, max(0, Int(box.midY * Double(grid))))
        var comp = connectedComponent(in: cand, seedX: cgx, seedY: cgy,
                                      x0: gx0, y0: gy0, x1: gx1, y1: gy1)
        // If the exact center wasn't foreground, seed from the nearest foreground cell.
        if comp == nil {
            outer: for r in 1...max(gx1 - gx0, gy1 - gy0) {
                for gy in max(gy0, cgy - r)...min(gy1, cgy + r) {
                    for gx in max(gx0, cgx - r)...min(gx1, cgx + r) where cand[gy][gx] {
                        comp = connectedComponent(in: cand, seedX: gx, seedY: gy,
                                                  x0: gx0, y0: gy0, x1: gx1, y1: gy1)
                        break outer
                    }
                }
            }
        }
        guard var mask = comp else { return nil }

        fillHoles(&mask, x0: gx0, y0: gy0, x1: gx1, y1: gy1)

        // Tight bounding box + a minimum-area sanity check.
        var minX = grid, minY = grid, maxX = 0, maxY = 0, count = 0
        for gy in gy0...gy1 {
            for gx in gx0...gx1 where mask[gy][gx] {
                minX = min(minX, gx); maxX = max(maxX, gx)
                minY = min(minY, gy); maxY = max(maxY, gy); count += 1
            }
        }
        guard count >= 16, maxX >= minX, maxY >= minY else { return nil }
        let bbox = CGRect(x: Double(minX) / Double(grid), y: Double(minY) / Double(grid),
                          width: Double(maxX - minX + 1) / Double(grid),
                          height: Double(maxY - minY + 1) / Double(grid))
        return (mask, bbox)
    }

    // MARK: - Blob helpers

    private static func connectedComponent(in cand: [[Bool]], seedX: Int, seedY: Int,
                                           x0: Int, y0: Int, x1: Int, y1: Int) -> [[Bool]]? {
        guard cand[seedY][seedX] else { return nil }
        var out = [[Bool]](repeating: [Bool](repeating: false, count: grid), count: grid)
        var stack = [(seedX, seedY)]
        out[seedY][seedX] = true
        while let (x, y) = stack.popLast() {
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                guard nx >= x0, nx <= x1, ny >= y0, ny <= y1 else { continue }
                if cand[ny][nx], !out[ny][nx] { out[ny][nx] = true; stack.append((nx, ny)) }
            }
        }
        return out
    }

    /// Flood "outside" from the box border through non-mask cells; anything not
    /// reached is an interior LiDAR hole → fill it in.
    private static func fillHoles(_ mask: inout [[Bool]], x0: Int, y0: Int, x1: Int, y1: Int) {
        var outside = [[Bool]](repeating: [Bool](repeating: false, count: grid), count: grid)
        var stack: [(Int, Int)] = []
        for gx in x0...x1 {
            for gy in [y0, y1] where !mask[gy][gx] && !outside[gy][gx] {
                outside[gy][gx] = true; stack.append((gx, gy))
            }
        }
        for gy in y0...y1 {
            for gx in [x0, x1] where !mask[gy][gx] && !outside[gy][gx] {
                outside[gy][gx] = true; stack.append((gx, gy))
            }
        }
        while let (x, y) = stack.popLast() {
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                guard nx >= x0, nx <= x1, ny >= y0, ny <= y1 else { continue }
                if !mask[ny][nx], !outside[ny][nx] { outside[ny][nx] = true; stack.append((nx, ny)) }
            }
        }
        for gy in y0...y1 {
            for gx in x0...x1 where !mask[gy][gx] && !outside[gy][gx] { mask[gy][gx] = true }
        }
    }

    // MARK: - Color

    private static func rgbaBuffer(frame: CapturedFrame) -> [UInt8]? {
        let w = Int(frame.imageWidth), h = Int(frame.imageHeight)
        guard w > 0, h > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(frame.cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private static func isSaturated(rgba: [UInt8], normX: Double, normY: Double, frame: CapturedFrame) -> Bool {
        let w = Int(frame.imageWidth), h = Int(frame.imageHeight)
        let px = min(w - 1, max(0, Int(normX * Double(w))))
        let py = min(h - 1, max(0, Int(normY * Double(h))))
        let o = (py * w + px) * 4
        let r = Double(rgba[o]) / 255, g = Double(rgba[o + 1]) / 255, b = Double(rgba[o + 2]) / 255
        let maxC = max(r, max(g, b)), minC = min(r, min(g, b))
        let sat = maxC > 0 ? (maxC - minC) / maxC : 0
        return maxC > 0.15 && sat > 0.30
    }

    private static func meanColor(mask: [[Bool]], frame: CapturedFrame) -> (hex: String, ripeness: String)? {
        guard let rgba = rgbaBuffer(frame: frame) else { return nil }
        let w = Int(frame.imageWidth), h = Int(frame.imageHeight)
        var sr = 0, sg = 0, sb = 0, n = 0
        for my in 0..<grid {
            for mx in 0..<grid where mask[my][mx] {
                let px = min(w - 1, max(0, Int(Double(mx) / Double(grid) * Double(w))))
                let py = min(h - 1, max(0, Int(Double(my) / Double(grid) * Double(h))))
                let o = (py * w + px) * 4
                sr += Int(rgba[o]); sg += Int(rgba[o + 1]); sb += Int(rgba[o + 2]); n += 1
            }
        }
        guard n > 0 else { return nil }
        let r = sr / n, g = sg / n, b = sb / n
        let rf = Float(r) / 255, gf = Float(g) / 255, bf = Float(b) / 255
        let maxC = max(rf, max(gf, bf)), minC = min(rf, min(gf, bf))
        var hue: Float = 0
        if maxC != minC {
            if maxC == rf { hue = (60 * ((gf - bf) / (maxC - minC)) + 360).truncatingRemainder(dividingBy: 360) }
            else if maxC == gf { hue = 60 * ((bf - rf) / (maxC - minC)) + 120 }
            else { hue = 60 * ((rf - gf) / (maxC - minC)) + 240 }
        }
        let ripeness = (hue < 45 || hue > 315) ? "Red" : "Green"
        return (String(format: "#%02X%02X%02X", r, g, b), ripeness)
    }

    private static func coarseShape(_ shapeIndex: Double?) -> String {
        guard let si = shapeIndex else { return "tomato" }
        if si < 1.15 { return "round" }
        if si < 1.40 { return "oval" }
        return "elongated"
    }
}
