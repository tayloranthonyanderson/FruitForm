import Foundation

enum CSVExporter {

    static let columns = [
        "timestamp", "session_id", "photo_filename", "accession", "capture_mode", "fruit_id",
        "major_axis_cm", "minor_axis_cm", "shape_index", "eccentricity", "flatness", "solidity",
        "volume_cm3", "weight_g_est", "semi_a_cm", "semi_b_cm", "semi_c_cm",
        "shape_category", "ripeness", "color_hex", "classifier_confidence", "depth_m", "occluded",
        "source", "note"
    ]

    /// Writes all measurements to a CSV file in the temp directory and returns
    /// its URL (for ShareLink). One row per fruit.
    static func export(_ measurements: [FruitMeasurement], fileName: String) throws -> URL {
        let iso = ISO8601DateFormatter()
        var rows = [columns.joined(separator: ",")]

        for m in measurements.sorted(by: { $0.timestamp < $1.timestamp }) {
            let fields: [String] = [
                iso.string(from: m.timestamp),
                m.sessionID.uuidString,
                "\(m.sessionID.uuidString).jpg",
                m.accession,
                m.captureMode.rawValue,
                m.id.uuidString,
                num(m.majorAxisCm),
                num(m.minorAxisCm),
                num(m.shapeIndex),
                num(m.eccentricity),
                num(m.flatness),
                num(m.solidity),
                num(m.volumeCm3),
                num(m.weightGramsEst),
                num(m.semiAxisACm),
                num(m.semiAxisBCm),
                num(m.semiAxisCCm),
                m.shapeCategory ?? "",
                m.ripeness ?? "",
                m.colorHex ?? "",
                num(m.classifierConfidence),
                num(m.depthMeters),
                m.occluded ? "1" : "0",
                m.source,
                m.note ?? ""
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }

        let csv = rows.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func num(_ v: Double?) -> String {
        guard let v = v else { return "" }
        return String(format: "%.4g", v)
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
