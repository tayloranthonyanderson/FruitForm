import SwiftUI

/// User-configurable settings. The API key is held in the keychain (device-only,
/// never written to the iCloud-backed defaults plist); the rest stay in
/// UserDefaults via `@AppStorage`.
final class AppSettings: ObservableObject {
    @AppStorage("claudeModel") var model: String = "claude-haiku-4-5-20251001"
    @AppStorage("cloudEnabled") var cloudEnabled: Bool = false
    @AppStorage("defaultAccession") var defaultAccession: String = ""

    /// Keychain-backed; reads/writes go straight to the keychain and notify
    /// observers so the SwiftUI `SecureField` binding stays two-way.
    var apiKey: String {
        get { Keychain.read() ?? "" }
        set {
            objectWillChange.send()
            Keychain.set(newValue)
        }
    }

    var cloudReady: Bool { cloudEnabled && !apiKey.isEmpty }
}
