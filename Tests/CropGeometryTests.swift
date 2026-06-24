import XCTest
import CoreGraphics
@testable import FruitForm

/// Regression guard for the crop-padding bug: the classifier crop must pad by a
/// fraction of the *box*, not the *image*. Padding by the image buried small fruit
/// in background and the classifier called everything flat/fasciated / rating 9.
final class CropGeometryTests: XCTestCase {

    func testPadIsFractionOfBoxNotImage() {
        // A small fruit: 10% of a 1000px frame, centred. Box = 100px.
        let norm = CGRect(x: 0.45, y: 0.45, width: 0.10, height: 0.10)
        let r = CropGeometry.paddedRect(normRect: norm, imageWidth: 1000, imageHeight: 1000, pad: 0.06)

        // Correct: 100px box + 6% of box each side = ~112px.
        XCTAssertEqual(r.width, 112, accuracy: 0.5)
        XCTAssertEqual(r.height, 112, accuracy: 0.5)

        // The bug padded by 6% of the IMAGE -> 100 + 2*60 = 220px. Guard against it.
        XCTAssertLessThan(r.width, 130, "crop must not be image-fraction padded (regression)")
    }

    func testPadScalesWithBoxSize() {
        // A big fruit and a small fruit should both keep ~12% extra, not a fixed
        // image-sized margin — proves the pad tracks the box.
        let big = CropGeometry.paddedRect(normRect: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
                                          imageWidth: 1000, imageHeight: 1000)
        let small = CropGeometry.paddedRect(normRect: CGRect(x: 0.45, y: 0.45, width: 0.05, height: 0.05),
                                            imageWidth: 1000, imageHeight: 1000)
        XCTAssertEqual(big.width / 400, small.width / 50, accuracy: 0.01)
    }

    func testClampsToImageBounds() {
        // A fruit at the edge can't produce a crop outside the image.
        let r = CropGeometry.paddedRect(normRect: CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2),
                                        imageWidth: 1000, imageHeight: 1000)
        XCTAssertGreaterThanOrEqual(r.minX, 0)
        XCTAssertGreaterThanOrEqual(r.minY, 0)
        XCTAssertLessThanOrEqual(r.maxX, 1000)
    }
}
