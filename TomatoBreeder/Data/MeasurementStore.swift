import Foundation
import Combine
import UIKit

/// A group of fruit captured in one shot.
struct CaptureSession: Identifiable {
    let id: UUID
    let accession: String
    let mode: CaptureMode
    let timestamp: Date
    var fruit: [FruitMeasurement]
}

/// Persists all measurements to a JSON file in Documents and exposes them
/// grouped into capture sessions for display.
final class MeasurementStore: ObservableObject {
    @Published private(set) var measurements: [FruitMeasurement] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("measurements.json")
    }()

    init() { load() }

    var sessions: [CaptureSession] {
        let groups = Dictionary(grouping: measurements, by: { $0.sessionID })
        return groups.values.compactMap { fruit -> CaptureSession? in
            guard let first = fruit.first else { return nil }
            return CaptureSession(id: first.sessionID,
                                  accession: first.accession,
                                  mode: first.captureMode,
                                  timestamp: first.timestamp,
                                  fruit: fruit)   // capture order — so list #N matches the image
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    func add(_ newFruit: [FruitMeasurement]) {
        measurements.append(contentsOf: newFruit)
        save()
    }

    func savePhoto(_ cgImage: CGImage, for sessionID: UUID) {
        let url = fileURL.deletingLastPathComponent().appendingPathComponent("\(sessionID.uuidString).jpg")
        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        guard let data = uiImage.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func photoURL(for sessionID: UUID) -> URL {
        return fileURL.deletingLastPathComponent().appendingPathComponent("\(sessionID.uuidString).jpg")
    }

    /// Photo with the detection masks drawn on it (for the Results "View image" screen).
    func saveAnnotatedPhoto(_ image: UIImage, for sessionID: UUID) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: annotatedPhotoURL(for: sessionID), options: .atomic)
    }

    func annotatedPhotoURL(for sessionID: UUID) -> URL {
        return fileURL.deletingLastPathComponent().appendingPathComponent("\(sessionID.uuidString)_annotated.jpg")
    }

    /// Best available image for a session: annotated if present, else the raw photo.
    func displayImage(for sessionID: UUID) -> UIImage? {
        if let img = UIImage(contentsOfFile: annotatedPhotoURL(for: sessionID).path) { return img }
        return UIImage(contentsOfFile: photoURL(for: sessionID).path)
    }

    // MARK: - Capture context (depth + per-fruit masks, for editing & recompute)

    private var dir: URL { fileURL.deletingLastPathComponent() }
    func contextURL(for id: UUID) -> URL { dir.appendingPathComponent("\(id.uuidString)_ctx.json") }
    func depthURL(for id: UUID) -> URL { dir.appendingPathComponent("\(id.uuidString).depth") }

    func saveContext(_ ctx: CaptureContext) {
        guard let data = try? JSONEncoder().encode(ctx) else { return }
        try? data.write(to: contextURL(for: ctx.sessionID), options: .atomic)
    }

    func saveDepth(_ values: [Float], for sessionID: UUID) {
        guard !values.isEmpty else { return }
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        try? data.write(to: depthURL(for: sessionID), options: .atomic)
    }

    func loadContext(for sessionID: UUID) -> CaptureContext? {
        guard let data = try? Data(contentsOf: contextURL(for: sessionID)) else { return nil }
        return try? JSONDecoder().decode(CaptureContext.self, from: data)
    }

    func loadDepth(for sessionID: UUID) -> [Float]? {
        guard let data = try? Data(contentsOf: depthURL(for: sessionID)), !data.isEmpty else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// Add a user-placed fruit the detector missed: store its measurement and
    /// append its geometry to the capture context so it persists and recomputes
    /// like any auto-detected fruit.
    func appendFruit(_ measurement: FruitMeasurement, stored: StoredFruit, to sessionID: UUID) {
        add([measurement])                       // appends + saves measurements (+ publishes)
        guard var ctx = loadContext(for: sessionID) else { return }
        ctx.fruit.append(stored)
        saveContext(ctx)
    }

    /// Exclude (or restore) a fruit — e.g. a false detection. It stays stored so
    /// it can be restored and keeps its number; excluded fruit are left out of
    /// the data summary and the CSV export.
    func setExcluded(_ measurementID: UUID, _ excluded: Bool) {
        guard let i = measurements.firstIndex(where: { $0.id == measurementID }) else { return }
        measurements[i].excluded = excluded
        save()
    }

    func deleteSession(_ id: UUID) {
        measurements.removeAll { $0.sessionID == id }
        for url in [photoURL(for: id), annotatedPhotoURL(for: id), contextURL(for: id), depthURL(for: id)] {
            try? FileManager.default.removeItem(at: url)
        }
        save()
    }

    func clearAll() {
        measurements.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder.iso.decode([FruitMeasurement].self, from: data) {
            measurements = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder.iso.encode(measurements) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
