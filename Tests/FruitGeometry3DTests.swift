import XCTest
import CoreGraphics
import simd
@testable import FruitForm

/// Numeric regression guard for the LiDAR → physical-size math in
/// `FruitGeometry3D.estimate` — the app's core value-prop. Feeds fully synthetic
/// geometry (a square mask at a known constant depth, with known intrinsics) and
/// checks the back-projected area, semi-axes, and volume against the closed-form
/// expectation. Deterministic: no model, no sensor, no image decode.
final class FruitGeometry3DTests: XCTestCase {

    // A 1px solid CGImage just to satisfy CapturedFrame; geometry never reads it.
    private func dummyImage() -> CGImage {
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                            bytesPerRow: 1, space: cs,
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        return ctx.makeImage()!
    }

    /// Square mask occupying the centre `side`×`side` block of the 160×160 grid.
    private func centeredSquareMask(side: Int) -> [[Bool]] {
        var mask = [[Bool]](repeating: [Bool](repeating: false, count: 160), count: 160)
        let lo = (160 - side) / 2, hi = lo + side
        for y in lo..<hi { for x in lo..<hi { mask[y][x] = true } }
        return mask
    }

    func testBackProjectedAreaAndVolumeMatchClosedForm() {
        // Camera/image geometry.
        let imageW = 1920.0, imageH = 1440.0
        let fx = 1500.0, fy = 1500.0
        let zMed = 0.40   // 40 cm, constant over the whole fruit

        // 40×40 cells of the 160×160 mask → a square silhouette.
        let side = 40
        let mask = centeredSquareMask(side: side)
        let validPixels = side * side

        let depthVals = [Float](repeating: Float(zMed), count: 64 * 48)
        let depth = DepthMap(width: 64, height: 48, values: depthVals)

        let frame = CapturedFrame(cgImage: dummyImage(), depth: depth,
                                  fx: fx, fy: fy, cx: imageW / 2, cy: imageH / 2,
                                  imageWidth: imageW, imageHeight: imageH,
                                  cameraTransform: matrix_identity_float4x4)
        let instance = TomatoInstance(rect: CGRect(x: 0.375, y: 0.375, width: 0.25, height: 0.25),
                                      confidence: 0.9, mask: mask)

        guard let est = FruitGeometry3D.estimate(instance: instance, frame: frame) else {
            return XCTFail("estimate returned nil for valid synthetic geometry")
        }

        // Closed-form physical area: each mask cell back-projects to
        // (imageW/160 · z/fx) × (imageH/160 · z/fy) metres².
        let cellW = imageW / 160.0, cellH = imageH / 160.0
        let pxAreaM2 = (cellW * zMed / fx) * (cellH * zMed / fy)
        let expectedAreaM2 = Double(validPixels) * pxAreaM2
        let expectedAreaCm2 = expectedAreaM2 * 100 * 100

        // Square box ⇒ aspect ratio 1 ⇒ aM == bM, and pi·a·b == area.
        let expectedSemiCm = sqrt(expectedAreaCm2 / .pi)

        XCTAssertEqual(est.fruitPixelCount, validPixels)
        XCTAssertEqual(est.medianDepthM, zMed, accuracy: 1e-6)
        XCTAssertEqual(est.semiAxisACm, expectedSemiCm, accuracy: 0.05)
        XCTAssertEqual(est.semiAxisBCm, expectedSemiCm, accuracy: 0.05)
        XCTAssertEqual(est.semiAxisACm, est.semiAxisBCm, accuracy: 1e-6)

        // Constant depth ⇒ measured thickness 0 ⇒ clamped to min(a,b)·0.5 ⇒
        // semi-axis c = min(a,b)·0.25.
        let expectedC = min(est.semiAxisACm, est.semiAxisBCm) * 0.5 / 2.0
        XCTAssertEqual(est.semiAxisCCm, expectedC, accuracy: 1e-6)

        // Volume = 4/3 · area(cm²) · c(cm).
        let expectedVolume = (4.0 / 3.0) * expectedAreaCm2 * est.semiAxisCCm
        XCTAssertEqual(est.volumeCm3, expectedVolume, accuracy: 0.5)

        // Sanity: a ~6 cm fruit lands in a physically plausible band, not 0 or 10⁴.
        XCTAssertGreaterThan(est.geometricMeanDiameterCm, 1.0)
        XCTAssertLessThan(est.geometricMeanDiameterCm, 30.0)
    }

    func testFlatnessFromBoxAspectRatio() {
        // A wider-than-tall box ⇒ aM (long in-plane axis) > bM, proving the
        // elliptical split tracks the bounding-box ratio.
        let imageW = 1920.0, imageH = 1440.0
        let mask = centeredSquareMask(side: 40)
        let depth = DepthMap(width: 32, height: 24,
                             values: [Float](repeating: 0.5, count: 32 * 24))
        let frame = CapturedFrame(cgImage: dummyImage(), depth: depth,
                                  fx: 1500, fy: 1500, cx: imageW / 2, cy: imageH / 2,
                                  imageWidth: imageW, imageHeight: imageH,
                                  cameraTransform: matrix_identity_float4x4)
        let instance = TomatoInstance(rect: CGRect(x: 0.2, y: 0.35, width: 0.6, height: 0.3),
                                      confidence: 0.9, mask: mask)

        guard let est = FruitGeometry3D.estimate(instance: instance, frame: frame) else {
            return XCTFail("estimate returned nil for valid synthetic geometry")
        }
        XCTAssertGreaterThan(est.semiAxisACm, est.semiAxisBCm)
    }

    func testReturnsNilWithoutDepth() {
        let frame = CapturedFrame(cgImage: dummyImage(), depth: nil,
                                  fx: 1500, fy: 1500, cx: 960, cy: 720,
                                  imageWidth: 1920, imageHeight: 1440,
                                  cameraTransform: matrix_identity_float4x4)
        let instance = TomatoInstance(rect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
                                      confidence: 0.9, mask: centeredSquareMask(side: 40))
        XCTAssertNil(FruitGeometry3D.estimate(instance: instance, frame: frame))
    }
}
