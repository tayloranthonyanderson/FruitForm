import SwiftUI

struct ReviewView: View {
    @ObservedObject var vm: CaptureViewModel
    @EnvironmentObject var store: MeasurementStore

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private func resetZoom() { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero }

    @ViewBuilder
    var body: some View {
        if let draft = vm.reviewDraft {
            ZStack {
                Color.black.ignoresSafeArea()

                GeometryReader { geo in
                    let cg = draft.frame.cgImage
                    let portraitAspect = CGFloat(cg.height) / CGFloat(cg.width)   // w/h after .right
                    let availH = geo.size.height - 90

                    let fittedByWidth = CGSize(width: geo.size.width, height: geo.size.width / portraitAspect)
                    let fittedByHeight = CGSize(width: availH * portraitAspect, height: availH)
                    let displaySize = fittedByWidth.height <= availH ? fittedByWidth : fittedByHeight

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        ZStack {
                            Image(uiImage: UIImage(cgImage: cg, scale: 1.0, orientation: .right))
                                .resizable()
                                .frame(width: displaySize.width, height: displaySize.height)
                            if let mask = vm.maskOverlayImage {
                                Image(uiImage: mask)
                                    .resizable()
                                    .frame(width: displaySize.width, height: displaySize.height)
                                    .allowsHitTesting(false)
                            }
                        }
                        .contentShape(Rectangle())
                        // Tap to toggle a fruit — location stays in displaySize space
                        // because zoom/pan are applied *after* this gesture.
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { v in vm.toggleFruit(at: v.location, in: displaySize) }
                        )
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { scale = min(6, max(1, lastScale * $0.magnification)) }
                                .onEnded { _ in lastScale = scale; if scale <= 1.02 { resetZoom() } }
                                .simultaneously(with:
                                    DragGesture(minimumDistance: 12)
                                        .onChanged { v in
                                            if scale > 1 {
                                                offset = CGSize(width: lastOffset.width + v.translation.width,
                                                                height: lastOffset.height + v.translation.height)
                                            }
                                        }
                                        .onEnded { _ in lastOffset = offset }
                                )
                        )

                        Spacer(minLength: 0)
                    }
                    .frame(height: availH)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .padding(.bottom, 90)

                // HUD
                VStack {
                    HStack {
                        let total = vm.reviewDraft?.measurements.count ?? 0
                        Text("\(vm.selectedFruitIDs.count) of \(total) selected")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                        if scale > 1.02 {
                            Button { withAnimation { resetZoom() } } label: {
                                Label("Reset", systemImage: "1.magnifyingglass")
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                        }
                    }
                    .padding()

                    Spacer()

                    Text("Pinch to zoom · drag to pan · tap a fruit to include/exclude")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())

                    HStack(spacing: 20) {
                        Button("Discard", role: .destructive) { vm.discardDraft() }
                            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                        Button("Save Session") { vm.saveDraft(store: store) }
                            .buttonStyle(.borderedProminent).tint(.blue).controlSize(.large)
                    }
                    .padding()
                }
            }
            .transition(.opacity)
            .zIndex(100)
        }
    }
}
