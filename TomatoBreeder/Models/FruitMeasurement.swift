import Foundation

/// One detected fruit from one capture. Size fields are nil when no LiDAR depth
/// was available (shape ratios are still valid — they're depth-independent).
struct FruitMeasurement: Identifiable, Codable, Hashable {
    var id = UUID()
    var accession: String
    var captureMode: CaptureMode
    var timestamp: Date
    var sessionID: UUID            // groups fruit captured in the same shot

    // --- Size (on-device, from LiDAR depth) ---
    var majorAxisCm: Double?       // longest extent of the silhouette
    var minorAxisCm: Double?       // perpendicular extent
    var depthMeters: Double?       // camera-to-fruit distance used for scaling

    // --- Volume (non-destructive, from silhouette + LiDAR depth shell) ---
    var volumeCm3: Double? = nil
    var weightGramsEst: Double? = nil   // volume × flesh density
    var semiAxisACm: Double? = nil      // ellipsoid semi-axes
    var semiAxisBCm: Double? = nil
    var semiAxisCCm: Double? = nil

    // --- Shape ---
    var shapeIndex: Double?        // major / minor (>= 1.0) of the silhouette
    var eccentricity: Double?      // sqrt(1 − (minor/major)²); 0 = circle, →1 = elongated
    var flatness: Double?          // LiDAR cap-height ÷ equatorial radius; <1 = oblate (provisional)
    var solidity: Double?          // area / convex-hull area; lower = more ribbed/lobed
    var shapeCategory: String?     // round, oval, plum, oxheart, ribbed, ...
    var classifierConfidence: Double?
    var shapeRating: Int?          // fruit_shape_rating trait: 1 (ideal) … 9 (cull)
    var shapeRatingConfidence: Double?
    var note: String?
    
    // --- Color ---
    var colorHex: String?
    var ripeness: String?          // "Red" or "Green"

    // --- Provenance / quality ---
    var occluded: Bool = false     // silhouette likely cut off by border or neighbor
    var source: String = "device"  // "device" or "device+cloud"
    var excluded: Bool = false      // user marked it not-a-tomato; kept (restorable), left out of data/export
}
