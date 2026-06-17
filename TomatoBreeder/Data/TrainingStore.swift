import SwiftUI
import UIKit

/// Manages the labeled training set: the label list, the per-label sample
/// counts, and writing each capture (photo + depth + metadata) to disk.
@MainActor
final class TrainingStore: ObservableObject {
    @Published private(set) var labels: [String] = []
    @Published private(set) var samples: [TrainingSample] = []

    private let dir: URL
    private let manifestURL: URL
    private let labelsKey = "trainingLabels"
    private let seedVersionKey = "trainingSeedVersion"
    private let currentSeedVersion = 3

    /// Preset tomato shape classes (editable — add/remove in the Training tab).
    /// UNSURE is a holding bin for fruit you can't confidently sort — kept out of
    /// the trained set but available to revisit, so users never force a wrong label.
    static let defaultShapeLabels = [
        "ROUND", "FLAT", "OVAL", "ELONGATED", "HEART", "PEAR", "FASCIATED", "UNSURE"
    ]
    /// Earlier presets we've since retired — removed on migration.
    static let deprecatedLabels: Set<String> = ["BLOCKY", "OXHEART", "RIBBED", "IRREGULAR"]

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("training", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        manifestURL = dir.appendingPathComponent("manifest.json")
        loadManifest()
        loadLabels()

        // Seed / migrate the preset shape classes: drop retired ones, add any new
        // ones, and keep the user's custom labels untouched.
        if UserDefaults.standard.integer(forKey: seedVersionKey) < currentSeedVersion {
            labels.removeAll { Self.deprecatedLabels.contains($0) }
            labels += Self.defaultShapeLabels.filter { !labels.contains($0) }
            saveLabels()
            UserDefaults.standard.set(currentSeedVersion, forKey: seedVersionKey)
        }
    }

    var totalCount: Int { samples.count }
    func count(for label: String) -> Int { samples.reduce(0) { $0 + ($1.label == label ? 1 : 0) } }

    // MARK: - Labels

    func addLabel(_ raw: String) {
        let l = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !l.isEmpty, !labels.contains(l) else { return }
        labels.append(l)
        saveLabels()
    }

    func removeLabel(_ l: String) {
        labels.removeAll { $0 == l }
        saveLabels()
    }

    /// Change a sample's shape label (fixing a mis-tag) without losing the photo/depth.
    func relabel(_ id: UUID, to newLabel: String) {
        let l = newLabel.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let i = samples.firstIndex(where: { $0.id == id }) else { return }
        samples[i].label = l
        if !labels.contains(l) { labels.append(l); saveLabels() }
        saveManifest()
    }

    // MARK: - Capture

    /// Saves the raw photo (native sensor orientation, so it aligns with depth +
    /// intrinsics), the depth map (raw Float32 meters), and a manifest entry.
    static let deviceModel: String = {
        var sys = utsname(); uname(&sys)
        let bytes = Mirror(reflecting: sys.machine).children.compactMap { $0.value as? Int8 }
        return String(bytes: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) },
                      encoding: .utf8) ?? "unknown"
    }()

    static let appVersion: String = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }()

    @discardableResult
    func save(frame: CapturedFrame, label: String) -> Bool {
        let m = frame.cameraTransform
        let transform: [Float] = [
            m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w,
            m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w,
            m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w,
            m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w
        ]
        let tilt = ARCaptureController.cameraTilt(m)
        let centerDist = frame.depth?
            .medianDepth(imageRect: CGRect(x: 0.45, y: 0.45, width: 0.10, height: 0.10))
            .map(Double.init)

        let sample = TrainingSample(
            id: UUID(), label: label, timestamp: Date(),
            imageWidth: Int(frame.imageWidth), imageHeight: Int(frame.imageHeight),
            fx: frame.fx, fy: frame.fy, cx: frame.cx, cy: frame.cy,
            depthWidth: frame.depth?.width ?? 0, depthHeight: frame.depth?.height ?? 0,
            cameraTransform: transform, tiltDegrees: tilt, centerDistanceM: centerDist,
            device: Self.deviceModel, appVersion: Self.appVersion)

        let image = UIImage(cgImage: frame.cgImage, scale: 1, orientation: .up)
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else { return false }
        do {
            try jpeg.write(to: dir.appendingPathComponent(sample.imageFile), options: .atomic)
            if let depth = frame.depth, !depth.values.isEmpty {
                let data = depth.values.withUnsafeBufferPointer { Data(buffer: $0) }
                try data.write(to: dir.appendingPathComponent(sample.depthFile), options: .atomic)
            }
        } catch { return false }

        samples.append(sample)
        saveManifest()
        return true
    }

    func deleteSample(_ id: UUID) {
        guard let s = samples.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(s.imageFile))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(s.depthFile))
        samples.removeAll { $0.id == id }
        saveManifest()
    }

    /// Zips the whole training directory (photos + .depth + manifest.json) into a
    /// temp file for AirDrop / Save-to-Files. Uses NSFileCoordinator's
    /// `.forUploading`, which archives a directory with no third-party deps.
    func exportArchive() -> URL? {
        let coordinator = NSFileCoordinator()
        var resultURL: URL?
        var coordErr: NSError?
        coordinator.coordinate(readingItemAt: dir, options: .forUploading, error: &coordErr) { tmpZip in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("tomato_training_set.zip")
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: tmpZip, to: dest)) != nil { resultURL = dest }
        }
        return resultURL
    }

    func deleteAll() {
        for s in samples {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(s.imageFile))
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(s.depthFile))
        }
        samples.removeAll()
        saveManifest()
    }

    /// The stored photo (raw sensor/landscape orientation).
    func image(for sample: TrainingSample) -> UIImage? {
        UIImage(contentsOfFile: dir.appendingPathComponent(sample.imageFile).path)
    }

    /// Same photo rotated upright for human viewing (files stay raw for training).
    func displayImage(for sample: TrainingSample) -> UIImage? {
        guard let cg = image(for: sample)?.cgImage else { return image(for: sample) }
        return UIImage(cgImage: cg, scale: 1, orientation: .right)
    }

    // MARK: - Persistence

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder.iso.decode([TrainingSample].self, from: data) else { return }
        samples = decoded
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder.iso.encode(samples) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func loadLabels() {
        guard let data = UserDefaults.standard.data(forKey: labelsKey),
              let l = try? JSONDecoder().decode([String].self, from: data) else { return }
        labels = l
    }

    private func saveLabels() {
        guard let data = try? JSONEncoder().encode(labels) else { return }
        UserDefaults.standard.set(data, forKey: labelsKey)
    }
}
