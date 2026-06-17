import SwiftUI
import simd

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var accession = ""
    @Published var mode: CaptureMode = .spread
    @Published var isProcessing = false
    @Published var lastSummary: String?
    @Published var errorMessage: String?
    @Published var reviewDraft: CaptureDraft?
    @Published var selectedFruitIDs: Set<UUID> = []
    @Published var maskOverlayImage: UIImage?

    private let processor = CaptureProcessor()

    func capture(controller: ARCaptureController, settings: AppSettings, store: MeasurementStore) {
        let acc = accession.isEmpty ? settings.defaultAccession : accession
        guard !acc.isEmpty else {
            errorMessage = "Enter an accession / plant ID first."
            return
        }
        guard let frame = controller.capture() else {
            errorMessage = "Couldn't read the camera — hold steady and try again."
            return
        }

        isProcessing = true
        errorMessage = nil
        lastSummary = nil
        let mode = self.mode

        Task {
            let draft = await processor.process(
                frame: frame, accession: acc, mode: mode,
                sessionID: UUID(), timestamp: Date(), settings: settings
            )
            isProcessing = false
            if draft.measurements.isEmpty {
                errorMessage = "No fruit detected. Fill more of the frame and keep good contrast with the ground."
            } else {
                selectedFruitIDs = Set(draft.measurements.map { $0.id })
                reviewDraft = draft
                regenerateMaskOverlay()
            }
        }
    }
    
    func saveDraft(store: MeasurementStore) {
        guard let draft = reviewDraft else { return }
        let selected = draft.measurements.filter { selectedFruitIDs.contains($0.id) }
        store.add(selected)
        
        if let sessionID = selected.first?.sessionID {
            store.savePhoto(draft.frame.cgImage, for: sessionID)
            if let annotated = renderAnnotatedImage() {
                store.saveAnnotatedPhoto(annotated, for: sessionID)
            }
            // Persist depth + per-fruit geometry so detections can be edited and
            // measurements recomputed later, without the live sensor.
            let stored = zip(draft.measurements, draft.instances)
                .filter { selectedFruitIDs.contains($0.0.id) }
                .map { (m, inst) in
                    StoredFruit(measurementID: m.id, confidence: inst.confidence,
                                rect: [inst.rect.minX, inst.rect.minY, inst.rect.width, inst.rect.height],
                                maskData: CaptureContext.packMask(inst.mask))
                }
            let t = draft.frame.cameraTransform
            let ctx = CaptureContext(
                sessionID: sessionID,
                imageWidth: Int(draft.frame.imageWidth), imageHeight: Int(draft.frame.imageHeight),
                fx: draft.frame.fx, fy: draft.frame.fy, cx: draft.frame.cx, cy: draft.frame.cy,
                depthWidth: draft.frame.depth?.width ?? 0, depthHeight: draft.frame.depth?.height ?? 0,
                cameraTransform: [t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
                                  t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
                                  t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
                                  t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w],
                fruit: stored)
            store.saveContext(ctx)
            store.saveDepth(draft.frame.depth?.values ?? [], for: sessionID)
        }
        
        let clean = selected.filter { !$0.occluded }.count
        let sized = selected.filter { $0.majorAxisCm != nil }.count
        lastSummary = "\(selected.count) saved · \(clean) clean · \(sized) sized"
        
        reviewDraft = nil
        selectedFruitIDs.removeAll()
        maskOverlayImage = nil
    }
    
    func discardDraft() {
        reviewDraft = nil
        selectedFruitIDs.removeAll()
        maskOverlayImage = nil
        lastSummary = "Shot discarded"
    }
    
    // MARK: - Tap handling
    
    func toggleFruit(at point: CGPoint, in displaySize: CGSize) {
        guard let draft = reviewDraft else { return }
        
        // 1. Normalize tap in displayed portrait image [0,1]
        let dispNX = point.x / displaySize.width
        let dispNY = point.y / displaySize.height
        
        // 2. Undo 90° CW rotation (.right) to get raw landscape image coords
        //    display→raw: rawX = dispY, rawY = 1 - dispX
        let imgNX = dispNY
        let imgNY = 1.0 - dispNX
        
        // 3. Image-normalized coords → mask grid (masks are image-space 160×160)
        let maskX = Int(imgNX * 160.0)
        let maskY = Int(imgNY * 160.0)
        
        guard maskX >= 0, maskX < 160, maskY >= 0, maskY < 160 else { return }
        
        // 4. Find which fruit was tapped (first mask hit wins)
        for (i, instance) in draft.instances.enumerated() {
            guard instance.mask[maskY][maskX] else { continue }
            guard i < draft.measurements.count else { continue }
            let id = draft.measurements[i].id
            if selectedFruitIDs.contains(id) {
                selectedFruitIDs.remove(id)
            } else {
                selectedFruitIDs.insert(id)
            }
            regenerateMaskOverlay()
            return
        }
    }
    
    /// Photo composited with the colored masks — saved as the session's record image.
    func renderAnnotatedImage() -> UIImage? {
        guard let draft = reviewDraft else { return nil }
        regenerateMaskOverlay()
        let photo = UIImage(cgImage: draft.frame.cgImage, scale: 1, orientation: .right)
        let size = photo.size
        guard size.width > 0, size.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            photo.draw(in: CGRect(origin: .zero, size: size))
            maskOverlayImage?.draw(in: CGRect(origin: .zero, size: size))

            // Number each saved fruit (capture order) so it matches the Results list.
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: max(14, size.width * 0.045)),
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black,
                .strokeWidth: -3.0
            ]
            var n = 0
            for (meas, inst) in zip(draft.measurements, draft.instances) {
                guard selectedFruitIDs.contains(meas.id), let c = Self.maskCentroid(inst.mask) else { continue }
                n += 1
                // sensor-normalized (rawX, rawY) → portrait display (.right): (1 − rawY, rawX)
                let pt = CGPoint(x: (1 - c.y) * size.width, y: c.x * size.height)
                let s = "\(n)" as NSString
                let sz = s.size(withAttributes: attrs)
                s.draw(at: CGPoint(x: pt.x - sz.width / 2, y: pt.y - sz.height / 2), withAttributes: attrs)
            }
        }
    }

    /// Centroid of a 160×160 mask in sensor-normalized [0,1] coords.
    static func maskCentroid(_ mask: [[Bool]]) -> CGPoint? {
        var sx = 0.0, sy = 0.0, n = 0.0
        for (y, row) in mask.enumerated() {
            for (x, v) in row.enumerated() where v {
                sx += Double(x); sy += Double(y); n += 1
            }
        }
        guard n > 0 else { return nil }
        return CGPoint(x: (sx / n) / 160.0, y: (sy / n) / 160.0)
    }

    // MARK: - Pre-rendered mask overlay

    /// Renders the mask overlay as a CGImage in the same coordinate space as the
    /// original landscape photo. Both get `.right` orientation so they align
    /// automatically — no manual rotation math in the view layer.
    func regenerateMaskOverlay() {
        guard let draft = reviewDraft else { maskOverlayImage = nil; return }
        
        let cgImage = draft.frame.cgImage
        // Render at 1/4 resolution to save memory (~3 MB for a 4032×3024 source)
        let renderW = min(cgImage.width, 1008)
        let renderH = cgImage.height * renderW / cgImage.width
        guard renderW > 0, renderH > 0 else { maskOverlayImage = nil; return }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: renderW, height: renderH,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { maskOverlayImage = nil; return }
        
        // Flip to top-left origin so drawing matches image pixel layout.
        // CGContext default is bottom-left; after this transform Y=0 is the top.
        ctx.translateBy(x: 0, y: CGFloat(renderH))
        ctx.scaleBy(x: 1, y: -1)
        
        // Masks are image-space 160×160, so one cell = renderW/160 × renderH/160.
        let cellW = CGFloat(renderW) / 160.0
        let cellH = CGFloat(renderH) / 160.0
        
        for (i, instance) in draft.instances.enumerated() {
            guard i < draft.measurements.count else { continue }
            let measurement = draft.measurements[i]
            let isSelected = selectedFruitIDs.contains(measurement.id)
            
            if isSelected {
                if measurement.ripeness == "Red" {
                    ctx.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.45)
                } else if measurement.ripeness == "Green" {
                    ctx.setFillColor(red: 0.0, green: 0.75, blue: 0.0, alpha: 0.45)
                } else {
                    ctx.setFillColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 0.45)
                }
            } else {
                ctx.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.35)
            }
            
            for my in 0..<160 {
                for mx in 0..<160 {
                    guard instance.mask[my][mx] else { continue }
                    let pX = CGFloat(mx) / 160.0 * CGFloat(renderW)
                    let pY = CGFloat(my) / 160.0 * CGFloat(renderH)
                    ctx.fill(CGRect(x: pX, y: pY, width: cellW + 0.5, height: cellH + 0.5))
                }
            }
        }
        
        guard let overlay = ctx.makeImage() else { maskOverlayImage = nil; return }
        // Same .right orientation as the photo — SwiftUI rotates both identically
        maskOverlayImage = UIImage(cgImage: overlay, scale: 1.0, orientation: .right)
    }
}
