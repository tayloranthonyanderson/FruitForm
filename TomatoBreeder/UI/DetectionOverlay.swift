import SwiftUI

/// Draws live fruit-detection boxes (with per-fruit distance) over the camera.
struct DetectionOverlay: View {
    let detections: [LiveDetection]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(detections) { d in
                let color: Color = d.occluded ? .orange : .green
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color, lineWidth: 3)
                    .frame(width: d.viewRect.width, height: d.viewRect.height)
                    .overlay(alignment: .top) {
                        if let dist = d.distanceM {
                            Text(String(format: "%.0f cm", dist * 100))
                                .font(.caption2.bold().monospacedDigit())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(color.opacity(0.9), in: Capsule())
                                .foregroundStyle(.black)
                                .fixedSize()
                                .offset(y: -20)
                        }
                    }
                    .position(x: d.viewRect.midX, y: d.viewRect.midY)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// Center crosshair with the live distance to whatever is in the middle.
struct CenterReticle: View {
    let distanceM: Float?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus.viewfinder")
                .font(.title)
                .foregroundStyle(.white.opacity(0.85))
                .shadow(radius: 3)
            Text(distanceM.map { String(format: "%.0f cm", $0 * 100) } ?? "— cm")
                .font(.callout.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .allowsHitTesting(false)
    }
}
