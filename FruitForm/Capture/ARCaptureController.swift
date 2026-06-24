import ARKit
import SceneKit
import Combine
import CoreImage
import UIKit

/// A fruit detected in the live preview, already mapped to on-screen view
/// coordinates so the overlay can draw it directly.
struct LiveDetection: Identifiable {
    let id: Int
    let viewRect: CGRect
    let distanceM: Float?
    let occluded: Bool
    /// Quick-look preview labels (only when "Preview data" is on). These come from
    /// the downscaled frame with no LiDAR/morphometrics — indicative, not the
    /// authoritative values produced at capture.
    var shape: String? = nil
    var rating: Int? = nil
}

/// Owns the ARKit session + preview view. Streams the live camera frames,
/// runs a throttled fruit detection for the on-screen overlay, and continuously
/// reports the center-of-frame distance. Full-resolution measurement still
/// happens on shutter via `capture()`.
final class ARCaptureController: NSObject, ObservableObject, ARSessionDelegate {
    let sceneView = ARSCNView(frame: .zero)
    private let ciContext = CIContext()
    private let detector = TomatoDetector()
    private let shapeClassifier = TomatoShapeClassifier()
    private let ratingClassifier = TomatoRatingClassifier()
    private let workQueue = DispatchQueue(label: "tomato.live.detect", qos: .userInitiated)

    @Published var lidarAvailable = true
    @Published var isRunning = false
    @Published var detections: [LiveDetection] = []
    @Published var centerDistanceM: Float?
    @Published var tiltDegrees: Double?     // camera tilt from straight-down (0 = top-down)
    @Published var liveCount = 0
    /// When on, the live overlay also shows a quick-look shape + rating per fruit
    /// (extra per-frame classifier passes; slows the overlay refresh a little).
    @Published var previewData = false

    /// Set from the SwiftUI layer so detections map to the right on-screen size.
    var viewportSize: CGSize = UIScreen.main.bounds.size

    private var isDetecting = false
    private var lastDetectTime: TimeInterval = 0
    private var lastDistanceTime: TimeInterval = 0
    private let detectInterval: TimeInterval = 0.30
    private let distanceInterval: TimeInterval = 0.12

    func start() {
        lidarAvailable = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        let config = ARWorldTrackingConfiguration()
        if lidarAvailable { config.frameSemantics.insert(.sceneDepth) }
        // Use the format that unlocks full-resolution (~12 MP) shutter stills via
        // captureHighResolutionFrame. LiDAR depth runs as a separate stream, so it
        // survives the format change; captureHighRes() still falls back if not.
        if let hiRes = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing {
            config.videoFormat = hiRes
        }
        config.worldAlignment = .gravity
        sceneView.session.delegate = self
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func pause() {
        sceneView.session.pause()
        isRunning = false
    }

    /// Live AR frame (1920×1440) — used as a depth-safe fallback.
    func capture() -> CapturedFrame? {
        guard let frame = sceneView.session.currentFrame else { return nil }
        return CapturedFrame(arFrame: frame, ciContext: ciContext)
    }

    /// Full-resolution still (~12 MP) captured at the shutter while the AR session
    /// keeps running. This is what gets stored + cropped for the classifier, so the
    /// archive is zoomable and the crops are sharp. Falls back to the live AR frame
    /// if the high-res frame is unavailable or lacks LiDAR depth (never lose depth).
    func captureHighRes() async -> CapturedFrame? {
        await withCheckedContinuation { (cont: CheckedContinuation<CapturedFrame?, Never>) in
            sceneView.session.captureHighResolutionFrame { [weak self] frame, _ in
                guard let self = self else { cont.resume(returning: nil); return }
                if let frame = frame, frame.sceneDepth != nil,
                   let cf = CapturedFrame(arFrame: frame, ciContext: self.ciContext) {
                    cont.resume(returning: cf)            // high-res WITH depth
                } else {
                    cont.resume(returning: self.capture()) // fallback keeps depth
                }
            }
        }
    }

    // MARK: - ARSessionDelegate (called on the main thread)

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let t = frame.timestamp

        // Cheap center-distance + camera-tilt readouts, throttled.
        if t - lastDistanceTime > distanceInterval {
            lastDistanceTime = t
            let d = Self.centerDistance(frame.sceneDepth?.depthMap)
            if d != centerDistanceM { centerDistanceM = d }
            let tilt = Self.cameraTilt(frame.camera.transform)
            if tilt != tiltDegrees { tiltDegrees = tilt }
        }

        // Throttled live fruit detection; skip if one is already running.
        guard !isDetecting, t - lastDetectTime > detectInterval else { return }
        lastDetectTime = t
        isDetecting = true

        let viewport = viewportSize
        let displayT = frame.displayTransform(for: .portrait, viewportSize: viewport)
        let preview = previewData   // read on main; used on the work queue

        // Extract everything we need *now* — the ARFrame's buffers are reused.
        guard let small = downscaledCGImage(frame.capturedImage, maxW: 768) else {
            isDetecting = false
            return
        }
        let depthMap = Self.makeDepthMap(frame.sceneDepth)

        workQueue.async { [weak self] in
            guard let self = self else { return }
            var dets: [LiveDetection] = []

            // Trained model: one box per fruit, any color, touching separated.
            // Vision boxes map straight through displayTransform (no x-flip).
            for (i, instance) in self.detector.detect(cgImage: small, computeMasks: false).enumerated() {
                let v = instance.rect.applying(displayT)
                let viewRect = CGRect(x: v.minX * viewport.width,
                                      y: v.minY * viewport.height,
                                      width: v.width * viewport.width,
                                      height: v.height * viewport.height)
                var dist: Float?
                if let depthMap = depthMap {
                    let inner = CGRect(x: instance.rect.midX - instance.rect.width * 0.15,
                                       y: instance.rect.midY - instance.rect.height * 0.15,
                                       width: instance.rect.width * 0.3,
                                       height: instance.rect.height * 0.3)
                    dist = depthMap.medianDepth(imageRect: inner)
                }
                let r = instance.rect
                let occluded = r.minX < 0.015 || r.maxX > 0.985 || r.minY < 0.015 || r.maxY > 0.985

                // Quick-look shape + rating on the downscaled crop (preview only).
                var shape: String?; var rating: Int?
                if preview, !occluded, let crop = self.cropNorm(small, normRect: r) {
                    shape = self.shapeClassifier.classify(cgImage: crop)?.label
                    rating = self.ratingClassifier.classify(cgImage: crop)?.rating
                }
                dets.append(LiveDetection(id: i, viewRect: viewRect, distanceM: dist,
                                          occluded: occluded, shape: shape, rating: rating))
            }

            DispatchQueue.main.async {
                self.detections = dets
                self.liveCount = dets.count
                self.isDetecting = false
            }
        }
    }

    // MARK: - Helpers

    /// Padded crop of one fruit from a CGImage given a normalized rect.
    private func cropNorm(_ image: CGImage, normRect: CGRect) -> CGImage? {
        // Shared box-proportional crop (see CropGeometry) so the preview matches the
        // classifier's training framing.
        let rect = CropGeometry.paddedRect(normRect: normRect,
                                           imageWidth: CGFloat(image.width), imageHeight: CGFloat(image.height))
        guard !rect.isNull, rect.width > 1, rect.height > 1 else { return nil }
        return image.cropping(to: rect)
    }

    private func downscaledCGImage(_ pixelBuffer: CVPixelBuffer, maxW: CGFloat) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = min(1, maxW / ci.extent.width)
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return ciContext.createCGImage(scaled, from: scaled.extent)
    }

    /// Angle (degrees) between the camera's optical axis and straight-down.
    /// 0° = pointing straight at the ground (top-down), 90° = horizontal.
    static func cameraTilt(_ transform: simd_float4x4) -> Double {
        // World is gravity-aligned (Y up); camera looks down its −Z axis.
        let cosTilt = max(-1, min(1, transform.columns.2.y))
        return Double(acos(cosTilt)) * 180.0 / .pi
    }

    /// Median depth (m) over a small central patch of the frame.
    static func centerDistance(_ depthMap: CVPixelBuffer?) -> Float? {
        guard let dm = depthMap else { return nil }
        CVPixelBufferLockBaseAddress(dm, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(dm, .readOnly) }
        let w = CVPixelBufferGetWidth(dm), h = CVPixelBufferGetHeight(dm)
        guard let base = CVPixelBufferGetBaseAddress(dm) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(dm)
        var samples: [Float] = []
        for dy in -3...3 {
            let y = h / 2 + dy
            guard y >= 0, y < h else { continue }
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
            for dx in -3...3 {
                let x = w / 2 + dx
                guard x >= 0, x < w else { continue }
                let v = row[x]
                if v.isFinite && v > 0 { samples.append(v) }
            }
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        return samples[samples.count / 2]
    }

    /// Copy the LiDAR depth buffer into a value type usable off the ARKit thread.
    static func makeDepthMap(_ sceneDepth: ARDepthData?) -> DepthMap? {
        guard let dm = sceneDepth?.depthMap else { return nil }
        CVPixelBufferLockBaseAddress(dm, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(dm, .readOnly) }
        let w = CVPixelBufferGetWidth(dm), h = CVPixelBufferGetHeight(dm)
        guard let base = CVPixelBufferGetBaseAddress(dm) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(dm)
        var values = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<w { values[y * w + x] = row[x] }
        }
        return DepthMap(width: w, height: h, values: values)
    }
}
