import UIKit

/// Renders a captured photo with per-fruit masks + numbers, from persisted data.
/// Used to refresh the Results image after the user edits detections.
enum AnnotatedRenderer {
    struct Fruit {
        let mask: [[Bool]]      // 160×160 image-space
        let ripeness: String?
        let number: Int
        let excluded: Bool
    }

    /// `photoCG` is the raw landscape sensor image; result is upright (.right).
    static func render(photoCG cg: CGImage, fruit: [Fruit]) -> UIImage? {
        let renderW = min(cg.width, 1280)
        let renderH = cg.height * renderW / cg.width
        guard renderW > 0, renderH > 0 else { return nil }

        // Mask overlay in landscape, top-left origin.
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let octx = CGContext(data: nil, width: renderW, height: renderH, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: cs,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        octx.translateBy(x: 0, y: CGFloat(renderH))
        octx.scaleBy(x: 1, y: -1)
        let cellW = CGFloat(renderW) / 160.0, cellH = CGFloat(renderH) / 160.0
        for f in fruit {
            if f.excluded { octx.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.30) }
            else if f.ripeness == "Red" { octx.setFillColor(red: 1, green: 0, blue: 0, alpha: 0.42) }
            else if f.ripeness == "Green" { octx.setFillColor(red: 0, green: 0.75, blue: 0, alpha: 0.42) }
            else { octx.setFillColor(red: 0.2, green: 0.5, blue: 1, alpha: 0.42) }
            for my in 0..<160 {
                for mx in 0..<160 where f.mask[my][mx] {
                    octx.fill(CGRect(x: CGFloat(mx) / 160 * CGFloat(renderW),
                                     y: CGFloat(my) / 160 * CGFloat(renderH),
                                     width: cellW + 0.5, height: cellH + 0.5))
                }
            }
        }
        guard let overlayCG = octx.makeImage() else { return nil }

        // Composite photo + overlay + numbers, upright.
        let photo = UIImage(cgImage: cg, scale: 1, orientation: .right)
        let overlay = UIImage(cgImage: overlayCG, scale: 1, orientation: .right)
        let size = photo.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            photo.draw(in: CGRect(origin: .zero, size: size))
            overlay.draw(in: CGRect(origin: .zero, size: size))
            let fontSize = max(14, size.width * 0.045)
            for f in fruit {
                guard let c = CaptureViewModel.maskCentroid(f.mask) else { continue }
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: fontSize),
                    .foregroundColor: f.excluded ? UIColor.lightGray : UIColor.white,
                    .strokeColor: UIColor.black, .strokeWidth: -3.0
                ]
                let pt = CGPoint(x: (1 - c.y) * size.width, y: c.x * size.height)
                let s = "\(f.number)" as NSString
                let sz = s.size(withAttributes: attrs)
                s.draw(at: CGPoint(x: pt.x - sz.width / 2, y: pt.y - sz.height / 2), withAttributes: attrs)
            }
        }
    }
}
