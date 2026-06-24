import ARKit
import CoreImage
import CoreVideo

/// A LiDAR depth map (meters), in the same sensor orientation as the captured
/// image. Coordinates are sampled in width-normalized isotropic space.
struct DepthMap {
    let width: Int
    let height: Int
    let values: [Float] // meters, row-major; 0 / non-finite means "no return"

    /// Median depth over a normalized rect (origin top-left, x in [0,1],
    /// y in [0, imageHeight/imageWidth]). Robust to LiDAR holes.
    func medianDepth(inNormalizedRect rect: CGRect, aspect: Double) -> Float? {
        guard width > 0, height > 0 else { return nil }
        // Convert width-normalized coords to depth-map pixels.
        func clampX(_ v: Double) -> Int { min(max(Int(v * Double(width)), 0), width - 1) }
        func clampY(_ v: Double) -> Int { min(max(Int(v / aspect * Double(height)), 0), height - 1) }
        let x0 = clampX(rect.minX), x1 = clampX(rect.maxX)
        let y0 = clampY(rect.minY), y1 = clampY(rect.maxY)
        var samples: [Float] = []
        var y = y0
        while y <= y1 {
            var x = x0
            while x <= x1 {
                let v = values[y * width + x]
                if v.isFinite && v > 0 { samples.append(v) }
                x += 1
            }
            y += 1
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        return samples[samples.count / 2]
    }

    /// Median depth over a standard-normalized image rect (x,y in [0,1],
    /// top-left origin). Used for model-box detections.
    func medianDepth(imageRect rect: CGRect) -> Float? {
        guard width > 0, height > 0 else { return nil }
        func cx(_ v: Double) -> Int { min(max(Int(v * Double(width)), 0), width - 1) }
        func cy(_ v: Double) -> Int { min(max(Int(v * Double(height)), 0), height - 1) }
        let x0 = cx(rect.minX), x1 = cx(rect.maxX)
        let y0 = cy(rect.minY), y1 = cy(rect.maxY)
        var samples: [Float] = []
        var y = y0
        while y <= y1 {
            var x = x0
            while x <= x1 {
                let v = values[y * width + x]
                if v.isFinite && v > 0 { samples.append(v) }
                x += 1
            }
            y += 1
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        return samples[samples.count / 2]
    }
}

/// Everything we extract from one ARFrame at capture time. The ARFrame itself is
/// not retained — its buffers are reused by ARKit, so we copy what we need.
struct CapturedFrame {
    let cgImage: CGImage
    let depth: DepthMap?
    let fx: Double            // focal length x (px) in image-resolution space
    let fy: Double            // focal length y (px)
    let cx: Double            // principal point x (px)
    let cy: Double            // principal point y (px)
    let imageWidth: Double
    let imageHeight: Double
    let cameraTransform: simd_float4x4   // camera pose in gravity-aligned world

    /// imageHeight / imageWidth — used to keep normalized coords isotropic.
    var aspect: Double { imageHeight / imageWidth }

    /// Rebuild a frame from persisted capture data (photo + depth binary +
    /// intrinsics) so edits can recompute measurements without the live sensor.
    init(cgImage: CGImage, depth: DepthMap?, fx: Double, fy: Double, cx: Double, cy: Double,
         imageWidth: Double, imageHeight: Double, cameraTransform: simd_float4x4) {
        self.cgImage = cgImage
        self.depth = depth
        self.fx = fx; self.fy = fy; self.cx = cx; self.cy = cy
        self.imageWidth = imageWidth; self.imageHeight = imageHeight
        self.cameraTransform = cameraTransform
    }

    init?(arFrame frame: ARFrame, ciContext: CIContext) {
        let ci = CIImage(cvPixelBuffer: frame.capturedImage)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        cgImage = cg

        let res = frame.camera.imageResolution
        imageWidth = Double(res.width)
        imageHeight = Double(res.height)
        let K = frame.camera.intrinsics
        fx = Double(K[0][0])
        fy = Double(K[1][1])
        cx = Double(K[2][0])
        cy = Double(K[2][1])
        cameraTransform = frame.camera.transform

        if let sceneDepth = frame.sceneDepth {
            let dm = sceneDepth.depthMap
            CVPixelBufferLockBaseAddress(dm, .readOnly)
            let w = CVPixelBufferGetWidth(dm)
            let h = CVPixelBufferGetHeight(dm)
            var values = [Float](repeating: 0, count: w * h)
            if let base = CVPixelBufferGetBaseAddress(dm) {
                let rowBytes = CVPixelBufferGetBytesPerRow(dm)
                for y in 0..<h {
                    let rowPtr = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
                    for x in 0..<w { values[y * w + x] = rowPtr[x] }
                }
            }
            CVPixelBufferUnlockBaseAddress(dm, .readOnly)
            depth = DepthMap(width: w, height: h, values: values)
        } else {
            depth = nil
        }
    }
}
