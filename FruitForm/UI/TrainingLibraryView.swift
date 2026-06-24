import SwiftUI

/// Browse every captured training photo (filterable by label), confirm what's
/// stored, and remove bad ones.
struct TrainingLibraryView: View {
    @EnvironmentObject var store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    @State private var modeFilter: TrainingMode?   // nil = all modes
    @State private var filter: String?             // nil = all categories
    @State private var detail: TrainingSample?
    @State private var exportItem: ExportItem?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    private var filtered: [TrainingSample] {
        store.samples
            .filter { modeFilter == nil || $0.trainingMode == modeFilter }
            .filter { filter == nil || $0.label == filter }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Category options for the label sub-filter, scoped to the selected mode.
    private var categoryOptions: [String] {
        modeFilter?.fixedCategories ?? store.labels
    }

    /// Toolbar label reflecting the active mode + category filters.
    private var filterLabel: String {
        switch (modeFilter, filter) {
        case (nil, nil):       return "All"
        case (let m?, nil):    return m.shortName
        case (nil, let f?):    return f
        case (let m?, let f?): return "\(m.shortName): \(f)"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.samples.isEmpty {
                    ContentUnavailableView("No training photos yet",
                                           systemImage: "photo.on.rectangle.angled",
                                           description: Text("Capture some in the Training tab — they'll show up here with their metadata."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(filtered) { sample in
                                Button { detail = sample } label: { cell(sample) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                    }
                }
            }
            .navigationTitle("Training set · \(store.totalCount)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Section("Mode") {
                            Button("All modes (\(store.totalCount))") { modeFilter = nil; filter = nil }
                            ForEach(TrainingMode.allCases) { m in
                                Button("\(m.shortName) (\(store.count(forMode: m)))") {
                                    modeFilter = m; filter = nil
                                }
                            }
                        }
                        Section(modeFilter?.displayName ?? "Category") {
                            Button("All categories") { filter = nil }
                            ForEach(categoryOptions, id: \.self) { l in
                                Button("\(l) · \(store.count(for: l, mode: modeFilter))") { filter = l }
                            }
                        }
                    } label: {
                        Label(filterLabel, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let url = store.exportArchive() { exportItem = ExportItem(url: url) }
                    } label: { Image(systemName: "square.and.arrow.up") }
                        .disabled(store.samples.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $detail) { TrainingSampleDetailView(sample: $0) }
            .sheet(item: $exportItem) { ShareSheet(activityItems: [$0.url]) }
        }
    }

    private func cell(_ s: TrainingSample) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let img = store.displayImage(for: s) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Rectangle().fill(.gray.opacity(0.3))
            }
            Text(s.trainingMode == .shapeRating ? "R\(s.label)" : s.label)
                .font(.caption2.bold())
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(s.trainingMode == .shapeRating
                            ? AnyShapeStyle(TrainingMode.ratingColor(for: s.label) ?? .gray)
                            : AnyShapeStyle(Color.black.opacity(0.6)))
                .foregroundStyle(.white)
                .padding(4)
        }
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Wraps the exported archive URL so it can drive a `.sheet(item:)`.
struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Minimal UIActivityViewController bridge for AirDrop / Save-to-Files.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Pinch-to-zoom + drag-to-pan image, with a reset control when zoomed.
struct ZoomableImageView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private func reset() { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero }

    var body: some View {
        Image(uiImage: image).resizable().scaledToFit()
            .scaleEffect(scale).offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { scale = min(6, max(1, lastScale * $0.magnification)) }
                    .onEnded { _ in lastScale = scale; if scale <= 1.02 { reset() } }
                    .simultaneously(with:
                        DragGesture(minimumDistance: 10)
                            .onChanged { v in
                                if scale > 1 {
                                    offset = CGSize(width: lastOffset.width + v.translation.width,
                                                    height: lastOffset.height + v.translation.height)
                                }
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
            )
            .overlay(alignment: .topTrailing) {
                if scale > 1.02 {
                    Button { withAnimation { reset() } } label: {
                        Image(systemName: "1.magnifyingglass")
                            .padding(8).background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(8)
                }
            }
            .background(Color.black)
            .clipped()
    }
}

/// Full photo + every stored field, with a delete control.
struct TrainingSampleDetailView: View {
    @EnvironmentObject var store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    let sample: TrainingSample
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let img = store.displayImage(for: sample) {
                    ZoomableImageView(image: img).frame(height: 360)
                }
                VStack(spacing: 6) {
                    HStack(alignment: .top) {
                        Text(sample.trainingMode == .shapeRating ? "Rating" : "Label")
                            .foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
                        Menu {
                            ForEach(sample.trainingMode.fixedCategories ?? store.labels, id: \.self) { l in
                                Button { store.relabel(sample.id, to: l); dismiss() } label: {
                                    if l == sample.label { Label(l, systemImage: "checkmark") } else { Text(l) }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(sample.trainingMode == .shapeRating ? "\(sample.label) — \(TrainingMode.ratingAnchors[sample.label] ?? "between")" : sample.label)
                                    .fontWeight(.semibold)
                                Image(systemName: "pencil").font(.caption2)
                            }
                        }
                        Spacer()
                    }
                    .font(.subheadline)
                    row("Mode", sample.trainingMode.displayName)
                    row("Captured", sample.timestamp.formatted(date: .abbreviated, time: .standard))
                    row("Distance", sample.centerDistanceM.map { String(format: "%.0f cm", $0 * 100) } ?? "—")
                    row("Tilt", String(format: "%.0f° from top-down", sample.tiltDegrees))
                    row("Image", "\(sample.imageWidth) × \(sample.imageHeight)")
                    row("Depth (LiDAR)", sample.depthWidth > 0 ? "\(sample.depthWidth) × \(sample.depthHeight) ✓" : "none ✗")
                    row("Focal fx, fy", String(format: "%.0f, %.0f", sample.fx, sample.fy))
                    row("Device", sample.device)
                    row("App", sample.appVersion)
                    row("ID", sample.id.uuidString)
                }
                .padding()
            }
            .navigationTitle("Sample")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Remove from training set", systemImage: "trash")
                    }
                }
            }
            .confirmationDialog("Remove this photo (and its depth) from the training set?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { store.deleteSample(sample.id); dismiss() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer()
        }
        .font(.subheadline)
    }
}
