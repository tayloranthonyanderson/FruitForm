import SwiftUI

/// Fast labeled data collection: pick a label chip, point, shoot. Each capture
/// stores the raw photo + LiDAR depth + intrinsics under the chosen label.
struct TrainingView: View {
    @EnvironmentObject var store: TrainingStore
    @StateObject private var controller = ARCaptureController()

    @State private var selectedLabel: String?
    @State private var showAddLabel = false
    @State private var newLabel = ""
    @State private var flash: String?
    @State private var showGuide = false
    @State private var showLibrary = false

    var body: some View {
        ZStack {
            CameraPreview(controller: controller)
                .ignoresSafeArea()

            DetectionOverlay(detections: controller.detections)

            VStack(spacing: 12) {
                HStack {
                    Button { showLibrary = true } label: {
                        Label("\(store.totalCount)", systemImage: "photo.stack.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                    Button { showGuide = true } label: {
                        Label("Shape guide", systemImage: "book.closed.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                labelBar
                Spacer()
                liveBadge
                HStack(spacing: 8) { distanceReadout; angleReadout }
                statusArea
                captureButton
            }
            .padding()
        }
        .sheet(isPresented: $showGuide) { ShapeGuideView() }
        .sheet(isPresented: $showLibrary) { TrainingLibraryView() }
        .onAppear {
            controller.start()
            if selectedLabel == nil { selectedLabel = store.labels.first }
        }
        .onDisappear { controller.pause() }
        .alert("New label", isPresented: $showAddLabel) {
            TextField("e.g. VARIETY_A or GRADE_CULL", text: $newLabel)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Add") {
                store.addLabel(newLabel)
                selectedLabel = newLabel.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                newLabel = ""
            }
            Button("Cancel", role: .cancel) { newLabel = "" }
        } message: {
            Text("Every capture is tagged with this label until you switch.")
        }
    }

    /// Live QA for the pre-sort workflow: every fruit the detector sees here will
    /// become a labeled sample under the selected shape when we train.
    private var liveBadge: some View {
        let count = controller.liveCount
        let label = selectedLabel ?? "—"
        return HStack(spacing: 6) {
            Image(systemName: count > 0 ? "checkmark.seal.fill" : "viewfinder")
                .foregroundStyle(count > 0 ? .green : .white)
            Text(count > 0
                 ? "^[\(count) fruit](inflect: true) detected → all labeled \(label)"
                 : "Point at your sorted \(label) fruit")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var labelBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.labels, id: \.self) { label in
                    Button { selectedLabel = label } label: {
                        HStack(spacing: 6) {
                            Text(label).fontWeight(.semibold)
                            Text("\(store.count(for: label))")
                                .font(.caption2)
                                .foregroundStyle(selectedLabel == label ? .white.opacity(0.85) : .secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background {
                            if selectedLabel == label { Capsule().fill(.green) }
                            else { Capsule().fill(.ultraThinMaterial) }
                        }
                        .foregroundStyle(selectedLabel == label ? .white : .primary)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            store.removeLabel(label)
                            if selectedLabel == label { selectedLabel = store.labels.first }
                        } label: { Label("Remove label", systemImage: "trash") }
                    }
                }
                Button { showAddLabel = true } label: {
                    Label("Add label", systemImage: "plus")
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(.ultraThinMaterial))
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Capture gating (distance + camera tilt)
    // Bands tuned to real field use: standing above a pile, sometimes oblique.

    private var distanceCm: Int? { controller.centerDistanceM.map { Int(($0 * 100).rounded()) } }
    private var tiltDeg: Int? { controller.tiltDegrees.map { Int($0.rounded()) } }

    private var distanceOK: Bool { (distanceCm.map { $0 >= 50 && $0 <= 160 }) ?? false }
    private var angleOK: Bool { (tiltDeg.map { $0 <= 60 }) ?? false }
    private var canShoot: Bool { selectedLabel != nil && distanceOK && angleOK }

    private var blockHint: String? {
        if selectedLabel == nil { return "Pick a shape label first" }
        guard let d = distanceCm else { return "Hold steady — finding the surface…" }
        if d < 50 { return "Too close — move back" }
        if d > 160 { return "Too far — move closer" }
        if let a = tiltDeg, a > 60 { return "Too sideways — aim more downward" }
        return nil
    }

    private func readout(_ icon: String, _ text: String, _ sub: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
            Text("· \(sub)").font(.caption2).foregroundStyle(.secondary)
        }
        .font(.subheadline.monospacedDigit().weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var distanceReadout: some View {
        let d = distanceCm
        let color: Color = d == nil ? .red
            : (d! >= 70 && d! <= 130) ? .green
            : (d! >= 50 && d! <= 160) ? .orange : .red
        return readout("ruler", d.map { "\($0) cm" } ?? "— cm", "70–130", color)
    }

    private var angleReadout: some View {
        let a = tiltDeg
        let color: Color = a == nil ? .red
            : (a! <= 40) ? .green
            : (a! <= 60) ? .orange : .red
        return readout("gyroscope", a.map { "\($0)°" } ?? "—°", "≤40° down", color)
    }

    @ViewBuilder private var statusArea: some View {
        if let flash {
            Label(flash, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .padding(10)
                .background(.ultraThinMaterial, in: Capsule())
        } else if let hint = blockHint {
            Label(hint, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.orange)
                .padding(10)
                .background(.ultraThinMaterial, in: Capsule())
        } else {
            Text("Fill the frame with one sorted shape  ·  \(store.totalCount) photos")
                .font(.subheadline.weight(.medium))
                .padding(10)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var captureButton: some View {
        Button(action: capture) {
            ZStack {
                Circle().fill(.white).frame(width: 74, height: 74)
                Circle().stroke(.white, lineWidth: 4).frame(width: 86, height: 86)
            }
        }
        .disabled(!canShoot)
        .opacity(canShoot ? 1 : 0.4)
        .padding(.bottom, 8)
    }

    private func capture() {
        guard canShoot, let label = selectedLabel, let frame = controller.capture() else { return }
        let fruitInView = controller.liveCount
        if store.save(frame: frame, label: label) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            let fruitNote = fruitInView > 0 ? "  ·  ~\(fruitInView) fruit" : ""
            flash = "Saved photo → \(label)\(fruitNote)  ·  \(store.count(for: label)) photos"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if flash?.hasPrefix("Saved") == true { flash = nil }
            }
        } else {
            flash = "Save failed — try again"
        }
    }
}
