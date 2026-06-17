import SwiftUI

struct CaptureView: View {
    @EnvironmentObject var store: MeasurementStore
    @EnvironmentObject var settings: AppSettings
    @StateObject private var controller = ARCaptureController()
    @StateObject private var vm = CaptureViewModel()

    var body: some View {
        ZStack {
            CameraPreview(controller: controller)
                .ignoresSafeArea()

            DetectionOverlay(detections: controller.detections)

            CenterReticle(distanceM: controller.centerDistanceM)

            VStack(spacing: 12) {
                topBar
                Spacer()
                liveBadge
                HStack(spacing: 8) { distanceReadout; angleReadout }
                statusArea
                captureButton
            }
            .padding()
            
            if vm.reviewDraft != nil {
                ReviewView(vm: vm)
            }
        }
        .animation(.easeInOut, value: vm.reviewDraft != nil)
        .onAppear {
            controller.start()
            if vm.accession.isEmpty { vm.accession = settings.defaultAccession }
        }
        .onDisappear { controller.pause() }
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "leaf.fill").foregroundStyle(.green)
                TextField("Accession / plant ID", text: $vm.accession)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

            Picker("Mode", selection: $vm.mode) {
                ForEach(CaptureMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Text(vm.mode.subtitle)
                .font(.caption)
                .foregroundStyle(.white)
                .shadow(radius: 2)

            if !controller.lidarAvailable {
                Label("No LiDAR on this device — shape is measured, but absolute size (cm) is unavailable.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var liveBadge: some View {
        let count = controller.liveCount
        return HStack(spacing: 6) {
            Image(systemName: count > 0 ? "checkmark.seal.fill" : "viewfinder")
                .foregroundStyle(count > 0 ? .green : .white)
            Text(count > 0
                 ? "^[\(count) fruit](inflect: true) in view"
                 : "Searching… aim at fruit on a plain background")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    @ViewBuilder private var statusArea: some View {
        if vm.isProcessing {
            HStack(spacing: 8) {
                ProgressView()
                Text("Analyzing…")
            }
            .padding(10)
            .background(.ultraThinMaterial, in: Capsule())
        } else if let summary = vm.lastSummary {
            Label(summary, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .padding(10)
                .background(.ultraThinMaterial, in: Capsule())
        } else if let error = vm.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        } else if let hint = blockHint {
            Label(hint, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.orange)
                .padding(10)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    // MARK: - Capture gating (distance + camera tilt)
    // Same bands as the Training screen so measurement shots are consistent with
    // the labeled data — and so distance/angle are in a range the math trusts.

    private var distanceCm: Int? { controller.centerDistanceM.map { Int(($0 * 100).rounded()) } }
    private var tiltDeg: Int? { controller.tiltDegrees.map { Int($0.rounded()) } }
    private var distanceOK: Bool { (distanceCm.map { $0 >= 50 && $0 <= 160 }) ?? false }
    private var angleOK: Bool { (tiltDeg.map { $0 <= 60 }) ?? false }
    private var canShoot: Bool { !vm.isProcessing && distanceOK && angleOK }

    private var blockHint: String? {
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

    private var captureButton: some View {
        Button {
            vm.capture(controller: controller, settings: settings, store: store)
        } label: {
            ZStack {
                Circle().fill(.white).frame(width: 74, height: 74)
                Circle().stroke(.white, lineWidth: 4).frame(width: 86, height: 86)
            }
        }
        .disabled(!canShoot)
        .opacity(canShoot ? 1 : 0.4)
        .padding(.bottom, 8)
    }
}
