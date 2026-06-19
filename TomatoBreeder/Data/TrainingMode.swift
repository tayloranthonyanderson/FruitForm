import SwiftUI

/// A selectable training-capture mode. Each mode tags every fruit in a pre-sorted
/// photo with one category (stored in `TrainingSample.label`); `TrainingSample.mode`
/// records which mode produced it so the two coexist in one manifest and stay
/// separable in the library and the ML pipeline.
///
/// Adding a new mode (e.g. ripeness, size grade) = one case here + its metadata.
/// The capture screen iterates `allCases` and reads everything off these properties,
/// so no UI rewiring is needed.
enum TrainingMode: String, CaseIterable, Identifiable, Codable {
    case shapeClass  = "shape_class"
    case shapeRating = "shape_rating"

    var id: String { rawValue }

    /// Default for samples with no stored mode — the legacy shape-class captures.
    static let `default`: TrainingMode = .shapeClass

    /// Full name for headers / detail rows.
    var displayName: String {
        switch self {
        case .shapeClass:  return "Shape class"
        case .shapeRating: return "Shape rating"
        }
    }

    /// Short name for the mode selector segment.
    var shortName: String {
        switch self {
        case .shapeClass:  return "Shape"
        case .shapeRating: return "Rating 1–9"
        }
    }

    /// The verb used in live-status copy ("…labeled OVAL" vs "…rated 3").
    var actionVerb: String {
        switch self {
        case .shapeClass:  return "labeled"
        case .shapeRating: return "rated"
        }
    }

    /// Are this mode's categories user-editable (add/remove), or a fixed set?
    var categoriesAreEditable: Bool {
        switch self {
        case .shapeClass:  return true
        case .shapeRating: return false
        }
    }

    /// Fixed categories for modes that have them; `nil` ⇒ pull from the store's
    /// editable label list. Rating order is 1 (best) … 9 (worst).
    var fixedCategories: [String]? {
        switch self {
        case .shapeClass:  return nil
        case .shapeRating: return (1...9).map(String.init)
        }
    }

    /// Whether category values are a 1…9 heat scale (drives the green→red tint).
    var isRatingScale: Bool { self == .shapeRating }

    /// One-line *example* (not a rule) for a category, shown under the picker and
    /// in the guide. nil for shape (ShapeGuideView already covers those).
    func anchorDescription(for category: String) -> String? {
        guard self == .shapeRating else { return nil }
        return Self.ratingAnchors[category]
    }

    /// Processing-tomato shape desirability. Loose, illustrative anchors on the odd
    /// steps; 2/4/6/8 are "between". Score on overall impression — many different
    /// defects can land a fruit at the same number.
    static let ratingAnchors: [String: String] = [
        "1": "Ideal — uniform oval/blocky paste type, smooth ends",
        "3": "Minor off — e.g. slightly uneven, a bit round, mild taper",
        "5": "Clearly off — e.g. mixed off-shapes, consistent lobing, irregular",
        "7": "Mostly cull — e.g. round/misshapen, too small or large; a few okay",
        "9": "Cull — round, lobed, or grossly irregular"
    ]

    /// Heat tint for a 1…9 rating chip: green (1, good) → amber (5) → red (9, bad).
    /// Returns nil for non-rating categories.
    static func ratingColor(for category: String) -> Color? {
        guard let v = Int(category), (1...9).contains(v) else { return nil }
        let t = Double(v - 1) / 8.0            // 0…1
        let hue = (1.0 - t) * 0.33             // 0.33 (green) → 0.0 (red)
        return Color(hue: hue, saturation: 0.85, brightness: 0.85)
    }
}
