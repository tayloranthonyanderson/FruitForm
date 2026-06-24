import XCTest
@testable import TomatoBreeder

final class TrainingModeTests: XCTestCase {

    func testRatingModeHasFixedNineCategories() {
        XCTAssertEqual(TrainingMode.shapeRating.fixedCategories, (1...9).map(String.init))
        XCTAssertNil(TrainingMode.shapeClass.fixedCategories,
                     "shape class pulls categories from the editable label list")
    }

    func testEditabilityDiffersByMode() {
        XCTAssertTrue(TrainingMode.shapeClass.categoriesAreEditable)
        XCTAssertFalse(TrainingMode.shapeRating.categoriesAreEditable)
    }

    func testRatingColorOnlyForValidDigits() {
        XCTAssertNotNil(TrainingMode.ratingColor(for: "1"))
        XCTAssertNotNil(TrainingMode.ratingColor(for: "9"))
        XCTAssertNil(TrainingMode.ratingColor(for: "oval"))
        XCTAssertNil(TrainingMode.ratingColor(for: "12"))
    }

    func testRawValuesAreStableStrings() {
        // On-disk manifests + the Python pipeline key off these — must not drift.
        XCTAssertEqual(TrainingMode.shapeClass.rawValue, "shape_class")
        XCTAssertEqual(TrainingMode.shapeRating.rawValue, "shape_rating")
        XCTAssertEqual(TrainingMode.default, .shapeClass)
    }

    func testLegacySampleWithoutModeReadsAsShapeClass() {
        // Old manifests have no `mode` key -> decodes nil -> must read as shape class.
        let json = #"{"id":"\#(UUID().uuidString)","label":"OVAL","timestamp":"2026-01-01T00:00:00Z","imageWidth":1920,"imageHeight":1440,"fx":1,"fy":1,"cx":1,"cy":1,"depthWidth":0,"depthHeight":0,"cameraTransform":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],"tiltDegrees":0,"device":"x","appVersion":"1"}"#
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let sample = try? dec.decode(TrainingSample.self, from: Data(json.utf8))
        XCTAssertEqual(sample?.trainingMode, .shapeClass)
    }
}
