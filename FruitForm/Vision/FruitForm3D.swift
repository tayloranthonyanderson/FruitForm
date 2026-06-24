import CoreGraphics

/// Recovers the fruit's out-of-plane (toward-camera) size from LiDAR depth — the
/// dimension a 2D silhouette can't see. This is what lets us tell a *flat/oblate*
/// fruit (which, resting pole-up under a top-down camera, projects a round-ish
/// top) from a genuinely round one.
///
/// PROVISIONAL: a single top-down view only sees the fruit's top cap, so the
/// polar height is a partial estimate. It's trustworthy enough to *flag* a
/// clearly flat fruit, but calibrate against caliper ground-truth before treating
/// `flatness` as an exact number.
struct FruitForm3D {
    var flatness: Double        // capThickness ÷ equatorial radius (≈1 round, <1 oblate)
    var formCategory: String?   // "flat" when convincingly oblate, else nil
}

enum FruitFormAnalyzer {

    static func analyze(instance: TomatoInstance, frame: CapturedFrame, shapeIndex: Double?) -> FruitForm3D? {
        guard let depth = frame.depth, depth.width > 0, depth.height > 0 else { return nil }

        var depths: [Float] = []
        var validCount = 0
        for my in 0..<160 {
            for mx in 0..<160 where instance.mask[my][mx] {
                let nx = Double(mx) / 160.0, ny = Double(my) / 160.0
                let dx = min(depth.width - 1, max(0, Int(nx * Double(depth.width))))
                let dy = min(depth.height - 1, max(0, Int(ny * Double(depth.height))))
                let z = depth.values[dy * depth.width + dx]
                if z.isFinite, z > 0 { depths.append(z); validCount += 1 }
            }
        }
        guard depths.count >= 12 else { return nil }
        depths.sort()

        // Top of the fruit (near) to its rim/equator (far), robust to outliers.
        let zNear = Double(depths[depths.count * 3 / 100])
        let zEquator = Double(depths[depths.count * 85 / 100])
        let cap = max(0, zEquator - zNear)              // ≈ pole→equator height (top half)

        // Equatorial radius from the silhouette area at the median fruit depth.
        let zMed = Double(depths[depths.count / 2])
        let cellW = frame.imageWidth / 160.0, cellH = frame.imageHeight / 160.0
        let pxAreaM2 = (cellW * zMed / frame.fx) * (cellH * zMed / frame.fy)
        let areaM2 = Double(validCount) * pxAreaM2
        let rEquator = (areaM2 / Double.pi).squareRoot()
        guard rEquator > 1e-4 else { return nil }

        let flatness = cap / rEquator

        // Only override to "flat" when the silhouette is round-ish — i.e. we're
        // looking roughly down the polar axis (pole-on), where 2D can't tell flat
        // from round. A clearly elongated silhouette is side-on; trust 2D there.
        var form: String?
        if let si = shapeIndex, si < 1.30, flatness < 0.65 { form = "flat" }

        return FruitForm3D(flatness: flatness, formCategory: form)
    }
}
