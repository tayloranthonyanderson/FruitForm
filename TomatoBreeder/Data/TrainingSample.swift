import Foundation

/// One labeled training capture: a raw photo + its LiDAR depth + camera
/// intrinsics + the user's label. Stored under Documents/training/.
struct TrainingSample: Codable, Identifiable {
    let id: UUID
    var label: String            // editable: user can relabel a mis-tagged sample
    let timestamp: Date
    let imageWidth: Int
    let imageHeight: Int
    let fx: Double
    let fy: Double
    let cx: Double
    let cy: Double
    let depthWidth: Int          // 0 if no LiDAR depth was available
    let depthHeight: Int

    // Capture geometry + provenance
    let cameraTransform: [Float] // 16, column-major, gravity-aligned world pose
    let tiltDegrees: Double      // camera angle from straight-down (0 = top-down)
    let centerDistanceM: Double? // LiDAR distance at the center of frame
    let device: String           // e.g. "iPhone15,3"
    let appVersion: String

    var imageFile: String { "\(id.uuidString).jpg" }
    var depthFile: String { "\(id.uuidString).depth" }   // raw Float32, row-major, meters
}
