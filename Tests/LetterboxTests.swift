import XCTest
@testable import FruitForm

/// The detector letterboxes the image into the model's 640² canvas; getting the
/// un-letterbox math wrong lands boxes/masks on the wrong fruit.
final class LetterboxTests: XCTestCase {

    func testModelImageRoundTripLandscape() {
        let lb = Letterbox(imageW: 1920, imageH: 1440)
        for (mx, my) in [(0.1, 0.2), (0.5, 0.5), (0.9, 0.8)] {
            let (ix, iy) = lb.toImage(mx, my)
            let (mx2, my2) = lb.toModel(Double(ix), Double(iy))
            XCTAssertEqual(mx2, mx, accuracy: 1e-9)
            XCTAssertEqual(my2, my, accuracy: 1e-9)
        }
    }

    func testLandscapePadsVertically() {
        // Wider-than-tall image: full width, letterboxed top/bottom.
        let lb = Letterbox(imageW: 1920, imageH: 1440)
        XCTAssertEqual(lb.scaledW, 1.0, accuracy: 1e-9)
        XCTAssertEqual(lb.padX, 0.0, accuracy: 1e-9)
        XCTAssertGreaterThan(lb.padY, 0.0)
    }
}
