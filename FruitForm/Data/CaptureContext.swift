import Foundation

/// One detected fruit's geometry, persisted so edits can recompute without the
/// live sensor. Linked back to its `FruitMeasurement` by id.
struct StoredFruit: Codable {
    let measurementID: UUID
    let confidence: Float
    let rect: [Double]       // normalized x, y, w, h (sensor/landscape space)
    let maskData: Data       // packed 160×160 bits (row-major)

    var mask: [[Bool]] { CaptureContext.unpackMask(maskData) }
}

/// The full reusable record of a capture: everything needed to redraw the
/// detections and recompute measurements after the user edits them. The depth
/// map is stored alongside as a separate binary file (`<sessionID>.depth`).
struct CaptureContext: Codable {
    let sessionID: UUID
    let imageWidth: Int
    let imageHeight: Int
    let fx: Double
    let fy: Double
    let cx: Double
    let cy: Double
    let depthWidth: Int
    let depthHeight: Int
    let cameraTransform: [Float]
    var fruit: [StoredFruit]

    // MARK: - Mask packing (160×160 booleans ⇄ 3200 bytes)

    static let maskGrid = 160

    static func packMask(_ mask: [[Bool]]) -> Data {
        var bytes = [UInt8](repeating: 0, count: (maskGrid * maskGrid + 7) / 8)
        var bit = 0
        for row in mask {
            for v in row {
                if v { bytes[bit >> 3] |= UInt8(1 << (bit & 7)) }
                bit += 1
            }
        }
        return Data(bytes)
    }

    static func unpackMask(_ data: Data) -> [[Bool]] {
        var mask = [[Bool]](repeating: [Bool](repeating: false, count: maskGrid), count: maskGrid)
        guard data.count >= (maskGrid * maskGrid + 7) / 8 else { return mask }
        var bit = 0
        for r in 0..<maskGrid {
            for c in 0..<maskGrid {
                if (data[bit >> 3] >> (bit & 7)) & 1 == 1 { mask[r][c] = true }
                bit += 1
            }
        }
        return mask
    }
}
