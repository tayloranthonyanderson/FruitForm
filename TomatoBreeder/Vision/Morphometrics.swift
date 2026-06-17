import CoreGraphics

/// Quantitative shape traits derived from a fruit's silhouette mask, in the
/// spirit of Tomato Analyzer. The fruit's principal **major axis** is used as a
/// proxy for the polar (stem–blossom) axis — approximate when the fruit isn't
/// lying with that axis in the image plane; refined later by pose estimation.
struct Morphometrics {
    var majorAxisCm: Double?
    var minorAxisCm: Double?
    var shapeIndex: Double?          // major / minor  (≥ 1)
    var eccentricity: Double?        // sqrt(1 − (minor/major)²); 0 = circle, →1 = elongated
    var solidity: Double?            // area / convex-hull area  (1 = smooth, lower = ribbed/lobed)
    var proximalBlockiness: Double?  // width near one pole ÷ widest width
    var distalBlockiness: Double?    // width near other pole ÷ widest width
    var asymmetry: Double?           // widest-point offset from center, −0.5…+0.5 (ovoid vs obovoid)
    var shapeCategory: String
}

enum MorphometricsAnalyzer {

    /// `depthM` (LiDAR median distance) is only needed to put the axes in cm;
    /// all the shape ratios are scale-independent and computed regardless.
    static func analyze(mask: [[Bool]], frame: CapturedFrame, depthM: Double?) -> Morphometrics? {
        let grid = mask.count
        guard grid > 0 else { return nil }
        let W = frame.imageWidth, H = frame.imageHeight

        // Mask cells → isotropic pixel-space points (square units).
        var pts: [Vec2] = []
        pts.reserveCapacity(512)
        for iy in 0..<grid {
            let row = mask[iy]
            let py = (Double(iy) + 0.5) / Double(grid) * H
            for ix in 0..<row.count where row[ix] {
                pts.append(Vec2(x: (Double(ix) + 0.5) / Double(grid) * W, y: py))
            }
        }
        guard pts.count >= 12,
              let frame3 = Geometry.principalFrame(points: pts),
              frame3.minorLen > 1e-6 else { return nil }

        let shapeIndex = frame3.majorLen / frame3.minorLen
        let eccentricity = shapeIndex > 1 ? (1 - 1 / (shapeIndex * shapeIndex)).squareRoot() : 0

        // Solidity from the convex hull. The hull must be built from the cells'
        // *corners* (their true extent), not their centers — otherwise the
        // center-hull is systematically smaller than the cell-counted area and
        // solidity clamps to 1.00 for every fruit.
        let sx = W / Double(grid), sy = H / Double(grid)
        let cellArea = sx * sy
        let area = Double(pts.count) * cellArea
        var hullPts: [Vec2] = []
        hullPts.reserveCapacity(pts.count * 4)
        for iy in 0..<grid {
            let row = mask[iy]
            for ix in 0..<row.count where row[ix] {
                let x0 = Double(ix) * sx, x1 = Double(ix + 1) * sx
                let y0 = Double(iy) * sy, y1 = Double(iy + 1) * sy
                hullPts.append(Vec2(x: x0, y: y0)); hullPts.append(Vec2(x: x1, y: y0))
                hullPts.append(Vec2(x: x0, y: y1)); hullPts.append(Vec2(x: x1, y: y1))
            }
        }
        let hullArea = Geometry.convexHullArea(points: hullPts)
        let solidity = hullArea > 1e-9 ? min(1.0, area / hullArea) : nil

        // Axes in cm (needs depth).
        var majorCm: Double?, minorCm: Double?
        if let z = depthM {
            let f = (frame.fx + frame.fy) / 2.0
            majorCm = frame3.majorLen * z / f * 100.0
            minorCm = frame3.minorLen * z / f * 100.0
        }

        // Width profile along the polar (major) axis.
        let profile = widthProfile(points: pts, frame3: frame3, bins: 24)
        let pb = profile.proximalBlockiness
        let db = profile.distalBlockiness
        let asym = profile.asymmetry

        // On a small silhouette the width profile is too noisy to trust the
        // "pointed end" signals (which drive heart/pear/oxheart) — suppress them.
        let pointingReliable = pts.count >= 250
        let category = classify(shapeIndex: shapeIndex, solidity: solidity,
                                proximalBlockiness: pb, distalBlockiness: db, asymmetry: asym,
                                pointingReliable: pointingReliable)

        return Morphometrics(majorAxisCm: majorCm, minorAxisCm: minorCm,
                             shapeIndex: shapeIndex, eccentricity: eccentricity, solidity: solidity,
                             proximalBlockiness: pb, distalBlockiness: db,
                             asymmetry: asym, shapeCategory: category)
    }

    // MARK: - Silhouette width profile

    private static func widthProfile(points: [Vec2],
                                     frame3: (centroid: Vec2, major: Vec2, minor: Vec2, majorLen: Double, minorLen: Double),
                                     bins: Int) -> (proximalBlockiness: Double?, distalBlockiness: Double?, asymmetry: Double?) {
        let c = frame3.centroid, m = frame3.major, n = frame3.minor
        var us = [Double](repeating: 0, count: points.count)
        var vs = [Double](repeating: 0, count: points.count)
        var uMin = Double.greatestFiniteMagnitude, uMax = -Double.greatestFiniteMagnitude
        for (i, p) in points.enumerated() {
            let dx = p.x - c.x, dy = p.y - c.y
            let u = dx * m.x + dy * m.y
            let v = dx * n.x + dy * n.y
            us[i] = u; vs[i] = v
            uMin = min(uMin, u); uMax = max(uMax, u)
        }
        let span = uMax - uMin
        guard span > 1e-6 else { return (nil, nil, nil) }

        var vLo = [Double](repeating: .greatestFiniteMagnitude, count: bins)
        var vHi = [Double](repeating: -.greatestFiniteMagnitude, count: bins)
        for i in 0..<points.count {
            var b = Int((us[i] - uMin) / span * Double(bins))
            if b < 0 { b = 0 }; if b >= bins { b = bins - 1 }
            vLo[b] = min(vLo[b], vs[i]); vHi[b] = max(vHi[b], vs[i])
        }
        var widths = [Double](repeating: 0, count: bins)
        for b in 0..<bins where vHi[b] >= vLo[b] { widths[b] = vHi[b] - vLo[b] }

        let maxW = widths.max() ?? 0
        guard maxW > 1e-6 else { return (nil, nil, nil) }

        func widthAt(_ frac: Double) -> Double {
            let b = min(bins - 1, max(0, Int(frac * Double(bins))))
            return widths[b]
        }
        let proximalBlockiness = widthAt(0.15) / maxW
        let distalBlockiness = widthAt(0.85) / maxW
        let widestFrac = (Double(widths.firstIndex(of: maxW) ?? bins / 2) + 0.5) / Double(bins)
        let asymmetry = widestFrac - 0.5

        return (proximalBlockiness, distalBlockiness, asymmetry)
    }

    // MARK: - Heuristic classification (the cloud model refines this when enabled)

    private static func classify(shapeIndex si: Double, solidity: Double?,
                                 proximalBlockiness pb: Double?, distalBlockiness db: Double?,
                                 asymmetry asym: Double?, pointingReliable: Bool) -> String {
        if let s = solidity, s < 0.88 { return "ribbed/lobed" }

        let p = pb ?? 1, d = db ?? 1
        let taperedEnd = min(p, d)        // < ~0.55 → a clearly pointed end
        let broadEnd = max(p, d)
        let pointed = pointingReliable && taperedEnd < 0.55
        let lopsided = pointingReliable && abs(asym ?? 0) > 0.12

        switch si {
        case ..<1.12:
            return "round"
        case ..<1.35:
            return pointed ? "heart" : "oval"
        case ..<1.9:
            if pointed && broadEnd > 0.8 { return "oxheart" }
            if lopsided { return "pear" }
            return "plum"
        default:
            return "elongated"
        }
    }
}
