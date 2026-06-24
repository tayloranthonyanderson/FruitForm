import CoreGraphics

/// Measures a detected fruit from its bounding box + LiDAR depth. Color-agnostic
/// (unlike the silhouette path), so it works for any variety the model finds.
enum BoxMeasurement {

    struct Result {
        var majorAxisCm: Double?
        var minorAxisCm: Double?
        var depthMeters: Double?
        var shapeIndex: Double?
        var occluded: Bool
    }

    static func measure(rect: CGRect, frame: CapturedFrame) -> Result {
        // Sample depth over the central third of the box (avoids the background
        // that sneaks into the box corners).
        let inner = CGRect(x: rect.midX - rect.width * 0.15,
                           y: rect.midY - rect.height * 0.15,
                           width: rect.width * 0.3,
                           height: rect.height * 0.3)
        let z = frame.depth?.medianDepth(imageRect: inner).map(Double.init)

        let wPx = Double(rect.width) * frame.imageWidth
        let hPx = Double(rect.height) * frame.imageHeight

        var majorCm: Double?
        var minorCm: Double?
        if let z = z, wPx > 0, hPx > 0 {
            let wCm = wPx * z / frame.fx * 100.0
            let hCm = hPx * z / frame.fx * 100.0
            majorCm = max(wCm, hCm)
            minorCm = min(wCm, hCm)
        }

        let shapeIndex = (wPx > 0 && hPx > 0) ? max(wPx, hPx) / min(wPx, hPx) : nil

        let m = 0.012
        let occluded = rect.minX < m || rect.maxX > 1 - m || rect.minY < m || rect.maxY > 1 - m

        return Result(majorAxisCm: majorCm, minorAxisCm: minorCm,
                      depthMeters: z, shapeIndex: shapeIndex, occluded: occluded)
    }
}
