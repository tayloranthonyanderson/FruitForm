import SwiftUI
import simd

struct ResultsView: View {
    @EnvironmentObject var store: MeasurementStore
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    ContentUnavailableView("No captures yet",
                                           systemImage: "camera.metering.none",
                                           description: Text("Photograph some tomatoes on the Capture tab."))
                } else {
                    List {
                        ForEach(store.sessions) { session in
                            NavigationLink {
                                SessionDetailView(sessionID: session.id)
                            } label: {
                                sessionRow(session)
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet { store.deleteSession(store.sessions[i].id) }
                        }
                    }
                }
            }
            .navigationTitle("Results")
            .toolbar {
                if let url = exportURL {
                    ShareLink(item: url) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .onAppear(perform: regenerateExport)
            .onChange(of: store.measurements) { _, _ in regenerateExport() }
        }
    }

    private func sessionRow(_ session: CaptureSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.accession).font(.headline)
                Spacer()
                Text(session.mode.title)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            let redCount = session.fruit.filter { $0.ripeness == "Red" }.count
            let greenCount = session.fruit.filter { $0.ripeness == "Green" }.count
            let colorSummary = redCount > 0 || greenCount > 0 ? " · \(redCount) Red · \(greenCount) Green" : ""
            Text("\(session.fruit.count) fruit\(colorSummary) · \(session.timestamp.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func regenerateExport() {
        let active = store.measurements.filter { !$0.excluded }
        guard !active.isEmpty else { exportURL = nil; return }
        exportURL = try? CSVExporter.export(active, fileName: "tomato_measurements.csv")
    }
}

struct SessionDetailView: View {
    @EnvironmentObject var store: MeasurementStore
    let sessionID: UUID
    @State private var showImage = false

    private var session: CaptureSession? { store.sessions.first { $0.id == sessionID } }

    var body: some View {
        Group {
            if let session {
                List {
                    Section {
                        ForEach(Array(session.fruit.enumerated()), id: \.element.id) { idx, fruit in
                            fruitRow(index: idx + 1, fruit: fruit)
                                .swipeActions(edge: .trailing) {
                                    if fruit.excluded {
                                        Button { store.setExcluded(fruit.id, false) } label: {
                                            Label("Restore", systemImage: "arrow.uturn.backward")
                                        }.tint(.green)
                                    } else {
                                        Button(role: .destructive) { store.setExcluded(fruit.id, true) } label: {
                                            Label("Exclude", systemImage: "xmark.circle")
                                        }
                                    }
                                }
                        }
                    } header: {
                        let active = session.fruit.filter { !$0.excluded }
                        let excluded = session.fruit.count - active.count
                        let red = active.filter { $0.ripeness == "Red" }.count
                        let green = active.filter { $0.ripeness == "Green" }.count
                        let colorSummary = red > 0 || green > 0 ? " · \(red) Red · \(green) Green" : ""
                        let exclSummary = excluded > 0 ? " · \(excluded) excluded" : ""
                        Text("\(active.count) fruit\(colorSummary)\(exclSummary) · \(session.mode.title)")
                    } footer: {
                        Text("Open “View image” to see numbered fruit, then tap one to remove or restore it. You can also swipe a row here.")
                    }
                }
                .navigationTitle(session.accession)
            } else {
                ContentUnavailableView("Session removed", systemImage: "trash")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showImage = true } label: { Label("View image", systemImage: "photo") }
            }
        }
        .sheet(isPresented: $showImage) {
            SessionImageView(sessionID: sessionID)
        }
    }

    private func fruitRow(index: Int, fruit: FruitMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("#\(index)").font(.headline)
                if fruit.excluded {
                    Text("Excluded").font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.gray.opacity(0.3), in: Capsule())
                }
                if let si = fruit.shapeIndex {
                    Text(String(format: "%.2f", si))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let cat = fruit.shapeCategory {
                    Text(cat)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
                if let rating = fruit.shapeRating {
                    Text("R\(rating)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(TrainingMode.ratingColor(for: String(rating)) ?? .gray,
                                    in: Capsule())
                }
                if let rip = fruit.ripeness {
                    Text(rip)
                        .font(.subheadline)
                        .foregroundStyle(rip == "Red" ? .red : .green)
                }
                if fruit.occluded {
                    Image(systemName: "eye.slash").foregroundStyle(.orange)
                }
                Spacer()
                if fruit.source == "device+cloud" {
                    Image(systemName: "cloud.fill").font(.caption).foregroundStyle(.blue)
                }
            }
            HStack(spacing: 16) {
                metric("Size", sizeString(fruit))
                metric("Eccentricity", fruit.eccentricity.map { String(format: "%.2f", $0) } ?? "—")
                metric("Solidity", fruit.solidity.map { String(format: "%.2f", $0) } ?? "—")
            }
            HStack(spacing: 16) {
                metric("Volume", fruit.volumeCm3.map { String(format: "%.1f cm³", $0) } ?? "—")
                metric("Weight~", fruit.weightGramsEst.map { String(format: "%.0f g", $0) } ?? "—")
                metric("Flatness", fruit.flatness.map { String(format: "%.2f", $0) } ?? "—")
            }
            if let note = fruit.note, !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .opacity(fruit.excluded ? 0.5 : 1)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit())
        }
    }

    private func sizeString(_ fruit: FruitMeasurement) -> String {
        guard let major = fruit.majorAxisCm, let minor = fruit.minorAxisCm else { return "—" }
        return String(format: "%.1f×%.1f cm", major, minor)
    }
}

/// Interactive image view: tap a fruit to toggle it in/out of the data (excluded
/// fruit grey out and drop from the export). Pinch to zoom, drag to pan. Switch
/// to Add mode to draw a box around a fruit the detector missed. Re-renders from
/// the persisted capture context after each edit.
struct SessionImageView: View {
    @EnvironmentObject var store: MeasurementStore
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID

    @State private var image: UIImage?
    @State private var context: CaptureContext?

    // Zoom / pan
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // Add-missed-fruit mode
    @State private var addMode = false
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var addError: String?

    private func resetZoom() { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero }

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    GeometryReader { geo in
                        let rect = fitRect(imageSize: image.size, in: geo.size)
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: image).resizable().scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                            if addMode, let box = currentDragRect() {
                                Rectangle().strokeBorder(.cyan, lineWidth: 2)
                                    .background(Color.cyan.opacity(0.15))
                                    .frame(width: box.width, height: box.height)
                                    .position(x: box.midX, y: box.midY)
                            }
                        }
                        // Pre-transform gestures: tap toggles a fruit (normal mode),
                        // drag draws the add-box (add mode). Both report locations in
                        // the un-zoomed content space, so mapping is zoom-independent.
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded {
                            if !addMode { toggleFruit(at: $0.location, imageRect: rect) }
                        })
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 6)
                                .onChanged { v in
                                    guard addMode else { return }
                                    if dragStart == nil { dragStart = v.startLocation }
                                    dragCurrent = v.location
                                }
                                .onEnded { _ in
                                    guard addMode else { return }
                                    defer { dragStart = nil; dragCurrent = nil }
                                    guard let box = currentDragRect() else { return }
                                    addFruit(displayRect: box, imageRect: rect)
                                }
                        )
                        .scaleEffect(scale)
                        .offset(offset)
                        // Post-transform: pinch to zoom, drag to pan (normal mode only).
                        .simultaneousGesture(
                            MagnifyGesture()
                                .onChanged { scale = min(6, max(1, lastScale * $0.magnification)) }
                                .onEnded { _ in lastScale = scale; if scale <= 1.02 { resetZoom() } }
                        )
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 12)
                                .onChanged { v in
                                    guard !addMode, scale > 1 else { return }
                                    offset = CGSize(width: lastOffset.width + v.translation.width,
                                                    height: lastOffset.height + v.translation.height)
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                        .overlay(alignment: .topTrailing) {
                            if scale > 1.02 {
                                Button { withAnimation { resetZoom() } } label: {
                                    Label("Reset", systemImage: "1.magnifyingglass")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(.ultraThinMaterial, in: Capsule())
                                }
                                .padding(10)
                            }
                        }
                    }
                    .background(Color.black)
                    .clipped()
                } else {
                    ContentUnavailableView("No image saved",
                                           systemImage: "photo.badge.exclamationmark",
                                           description: Text("This capture predates image saving. New captures include the photo + sensor data."))
                }
            }
            .navigationTitle("Captured image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .onAppear(perform: reload)
        }
    }

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 10) {
            if addMode {
                Text("Drag a box around the fruit the detector missed.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let addError {
                    Text(addError).font(.caption).foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                Button(role: .cancel) { exitAddMode() } label: {
                    Label("Cancel", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
            } else {
                Text("Tap a fruit to remove it (greys out); tap again to restore. Pinch to zoom.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    addError = nil; addMode = true
                } label: {
                    Label("Add a missed fruit", systemImage: "plus.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func exitAddMode() {
        addMode = false; dragStart = nil; dragCurrent = nil; addError = nil
    }

    private func reload() {
        context = store.loadContext(for: sessionID)
        if let ctx = context,
           let cg = UIImage(contentsOfFile: store.photoURL(for: sessionID).path)?.cgImage {
            let byID = Dictionary(store.measurements.filter { $0.sessionID == sessionID }.map { ($0.id, $0) },
                                  uniquingKeysWith: { a, _ in a })
            let fruit = ctx.fruit.enumerated().map { i, sf -> AnnotatedRenderer.Fruit in
                let m = byID[sf.measurementID]
                return AnnotatedRenderer.Fruit(mask: sf.mask, ripeness: m?.ripeness,
                                               number: i + 1, excluded: m?.excluded ?? false)
            }
            if let rendered = AnnotatedRenderer.render(photoCG: cg, fruit: fruit) {
                image = rendered
                store.saveAnnotatedPhoto(rendered, for: sessionID)
                return
            }
        }
        image = store.displayImage(for: sessionID)
    }

    /// Single tap directly toggles the tapped fruit's excluded state.
    private func toggleFruit(at p: CGPoint, imageRect: CGRect) {
        guard let ctx = context, imageRect.contains(p) else { return }
        let dispX = (p.x - imageRect.minX) / imageRect.width
        let dispY = (p.y - imageRect.minY) / imageRect.height
        // portrait display → raw sensor: rawX = dispY, rawY = 1 − dispX
        let mx = Int(dispY * 160), my = Int((1 - dispX) * 160)
        guard mx >= 0, mx < 160, my >= 0, my < 160 else { return }
        for sf in ctx.fruit where sf.mask[my][mx] {
            let nowExcluded = store.measurements.first { $0.id == sf.measurementID }?.excluded ?? false
            store.setExcluded(sf.measurementID, !nowExcluded)
            reload()
            return
        }
    }

    private func fitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    // MARK: - Add a missed fruit

    /// Current rubber-band rectangle in display (view) coordinates.
    private func currentDragRect() -> CGRect? {
        guard let a = dragStart, let b = dragCurrent else { return nil }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func addFruit(displayRect: CGRect, imageRect: CGRect) {
        let clamped = displayRect.intersection(imageRect)
        guard clamped.width > 6, clamped.height > 6 else {
            addError = "Box too small — drag a larger box around the fruit."; return
        }
        guard let frame = reconstructFrame() else {
            addError = "This capture has no saved sensor data to add fruit from."; return
        }
        // display point → display-normalized [0,1]
        func dn(_ p: CGPoint) -> (Double, Double) {
            ((p.x - imageRect.minX) / imageRect.width, (p.y - imageRect.minY) / imageRect.height)
        }
        let (nx0, ny0) = dn(CGPoint(x: clamped.minX, y: clamped.minY))
        let (nx1, ny1) = dn(CGPoint(x: clamped.maxX, y: clamped.maxY))
        // portrait display (.right) → raw sensor: rawX = dispY, rawY = 1 − dispX
        let rawXmin = min(ny0, ny1), rawXmax = max(ny0, ny1)
        let rawYmin = 1 - max(nx0, nx1), rawYmax = 1 - min(nx0, nx1)
        let rawBox = CGRect(x: rawXmin, y: rawYmin, width: rawXmax - rawXmin, height: rawYmax - rawYmin)

        let base = store.measurements.first { $0.sessionID == sessionID }
        guard let result = ManualFruit.build(
            rawBox: rawBox, frame: frame,
            accession: base?.accession ?? "",
            mode: base?.captureMode ?? .spread,
            sessionID: sessionID,
            timestamp: base?.timestamp ?? Date()
        ) else {
            addError = "Couldn't find a fruit in that box — try a tighter box around a single fruit."
            return
        }
        store.appendFruit(result.0, stored: result.1, to: sessionID)
        exitAddMode()
        reload()
    }

    private func reconstructFrame() -> CapturedFrame? {
        guard let ctx = context,
              let cg = UIImage(contentsOfFile: store.photoURL(for: sessionID).path)?.cgImage else { return nil }
        var depth: DepthMap?
        if ctx.depthWidth > 0, ctx.depthHeight > 0,
           let vals = store.loadDepth(for: sessionID), vals.count == ctx.depthWidth * ctx.depthHeight {
            depth = DepthMap(width: ctx.depthWidth, height: ctx.depthHeight, values: vals)
        }
        let t = ctx.cameraTransform
        let transform: simd_float4x4 = t.count == 16
            ? simd_float4x4(SIMD4(t[0], t[1], t[2], t[3]), SIMD4(t[4], t[5], t[6], t[7]),
                            SIMD4(t[8], t[9], t[10], t[11]), SIMD4(t[12], t[13], t[14], t[15]))
            : matrix_identity_float4x4
        return CapturedFrame(cgImage: cg, depth: depth,
                             fx: ctx.fx, fy: ctx.fy, cx: ctx.cx, cy: ctx.cy,
                             imageWidth: Double(ctx.imageWidth), imageHeight: Double(ctx.imageHeight),
                             cameraTransform: transform)
    }
}
