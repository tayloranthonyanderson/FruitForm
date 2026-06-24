import SwiftUI

/// User-configurable settings. The API key lives in UserDefaults for v1 — note
/// to self: move to Keychain before this leaves your own devices.
final class AppSettings: ObservableObject {
    @AppStorage("anthropicAPIKey") var apiKey: String = ""
    @AppStorage("claudeModel") var model: String = "claude-haiku-4-5-20251001"
    @AppStorage("cloudEnabled") var cloudEnabled: Bool = false
    @AppStorage("defaultAccession") var defaultAccession: String = ""

    var cloudReady: Bool { cloudEnabled && !apiKey.isEmpty }
}
