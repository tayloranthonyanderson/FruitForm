import Foundation

/// How the fruit was presented to the camera. This drives how aggressively we
/// trust per-fruit numbers vs. treat the shot as an aggregate sample.
enum CaptureMode: String, Codable, CaseIterable, Identifiable {
    case spread   // single layer, raked flat — clean per-fruit data
    case pile     // pile as-is — count + only fully-visible top fruit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spread: return "Spread"
        case .pile:   return "Quick Pile"
        }
    }

    var subtitle: String {
        switch self {
        case .spread: return "Single layer — measures every visible fruit"
        case .pile:   return "Pile as-is — count + top fruit only"
        }
    }
}
