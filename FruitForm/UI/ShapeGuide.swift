import SwiftUI

/// Reference info for one tomato shape class.
struct TomatoShapeInfo: Identifiable {
    let key: String
    let title: String
    let description: String
    var id: String { key }
}

let tomatoShapeGuide: [TomatoShapeInfo] = [
    .init(key: "ROUND", title: "Round / globe",
          description: "Spherical — about as wide as it is tall. Cherry, cocktail, and many fresh types."),
    .init(key: "FLAT", title: "Flat / oblate",
          description: "Clearly wider than tall, flattened top and bottom. Classic beefsteak / slicer."),
    .init(key: "OVAL", title: "Oval / plum",
          description: "Egg-shaped — a bit taller than wide with smoothly rounded ends. Roma."),
    .init(key: "ELONGATED", title: "Elongated / long",
          description: "Much taller than wide, cylindrical. San Marzano, banana, long paste types."),
    .init(key: "HEART", title: "Heart",
          description: "Rounded shoulders tapering to a blunt point at the blossom end."),
    .init(key: "PEAR", title: "Pear / pyriform",
          description: "A narrow neck at the stem end widening to a bulbous base. Teardrop."),
    .init(key: "FASCIATED", title: "Fasciated",
          description: "Large, flattened and convoluted — deep ribbing plus irregular lobing from fused locules. The creased beefsteak-heirloom look.")
]

/// A schematic tomato silhouette for each shape class.
struct TomatoSilhouette: Shape {
    let kind: String

    func path(in rect: CGRect) -> Path {
        switch kind {
        case "ROUND":     return ellipse(rect, 0.78, 0.78)
        case "FLAT":      return ellipse(rect, 0.90, 0.58)
        case "OVAL":      return ellipse(rect, 0.58, 0.84)
        case "ELONGATED": return ellipse(rect, 0.36, 0.92)
        case "HEART":     return heart(rect, breadth: 0.44, pointY: 0.92, notchY: 0.26)
        case "PEAR":      return pear(rect)
        case "FASCIATED": return fasciated(rect)
        default:          return ellipse(rect, 0.78, 0.78)
        }
    }

    private func ellipse(_ rect: CGRect, _ wf: CGFloat, _ hf: CGFloat) -> Path {
        let w = rect.width * wf, h = rect.height * hf
        return Path(ellipseIn: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }

    private func heart(_ rect: CGRect, breadth: CGFloat, pointY: CGFloat, notchY: CGFloat) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        let lx = 0.5 - breadth, rx = 0.5 + breadth
        var p = Path()
        p.move(to: pt(0.5, pointY))
        p.addCurve(to: pt(lx, 0.37), control1: pt(0.42, pointY - 0.15), control2: pt(lx, 0.6))
        p.addCurve(to: pt(0.5, notchY), control1: pt(lx, 0.07), control2: pt(0.42, 0.06))
        p.addCurve(to: pt(rx, 0.37), control1: pt(0.58, 0.06), control2: pt(rx, 0.07))
        p.addCurve(to: pt(0.5, pointY), control1: pt(rx, 0.6), control2: pt(0.58, pointY - 0.15))
        p.closeSubpath()
        return p
    }

    private func pear(_ rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var p = Path()
        p.move(to: pt(0.5, 0.07))
        p.addCurve(to: pt(0.84, 0.74), control1: pt(0.64, 0.16), control2: pt(0.84, 0.46))
        p.addCurve(to: pt(0.5, 0.96), control1: pt(0.84, 0.90), control2: pt(0.68, 0.96))
        p.addCurve(to: pt(0.16, 0.74), control1: pt(0.32, 0.96), control2: pt(0.16, 0.90))
        p.addCurve(to: pt(0.5, 0.07), control1: pt(0.16, 0.46), control2: pt(0.36, 0.16))
        p.closeSubpath()
        return p
    }

    /// Fasciated: large, flattened, with deep ribbing + irregular asymmetry.
    private func fasciated(_ rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, cy = rect.midY
        let baseR = min(rect.width, rect.height) * 0.46
        let flatten: CGFloat = 0.72
        let n = 240
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n) * 2 * .pi
            let r = baseR * (1 + 0.16 * cos(8 * t) + 0.07 * sin(3 * t + 1.0) + 0.04 * cos(5 * t + 2.0))
            let point = CGPoint(x: cx + r * cos(t), y: cy + r * sin(t) * flatten)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }
}

/// 5-point calyx (sepal) star, drawn green above the fruit.
struct CalyxStar: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, cy = rect.midY
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.45
        let points = 5
        for i in 0..<(points * 2) {
            let r = i % 2 == 0 ? outer : inner
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(points)
            let point = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }
}

/// Red fruit silhouette + a little green calyx — one schematic tomato.
struct ShapeIllustration: View {
    let kind: String
    var body: some View {
        GeometryReader { geo in
            ZStack {
                TomatoSilhouette(kind: kind)
                    .fill(Color(red: 0.85, green: 0.23, blue: 0.18))
                CalyxStar()
                    .fill(Color(red: 0.27, green: 0.55, blue: 0.20))
                    .frame(width: geo.size.width * 0.22, height: geo.size.width * 0.22)
                    .position(x: geo.size.width * 0.5, y: geo.size.height * 0.12)
            }
        }
    }
}

/// The full reference sheet listing every shape class.
struct ShapeGuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(tomatoShapeGuide) { info in
                HStack(spacing: 14) {
                    ShapeIllustration(kind: info.key)
                        .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(info.title).font(.headline)
                        Text(info.description).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Tomato shape guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

/// Reference sheet for the 1–9 shape-rating scale. Anchors are illustrative
/// examples on the odd steps, not a rubric.
struct RatingGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Score on overall impression — sort piles relative to each other rather than matching a definition. Many different defects can land a fruit at the same number. 1 = ideal processing shape, 9 = cull.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(1...9, id: \.self) { v in
                        let digit = String(v)
                        HStack(spacing: 14) {
                            Text(digit)
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(TrainingMode.ratingColor(for: digit) ?? .gray))
                            Text(TrainingMode.ratingAnchors[digit] ?? "Between the steps above and below")
                                .font(.subheadline)
                                .foregroundStyle(TrainingMode.ratingAnchors[digit] == nil ? .secondary : .primary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Shape rating 1–9")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
