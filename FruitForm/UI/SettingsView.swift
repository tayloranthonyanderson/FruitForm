import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var store: MeasurementStore
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Capture") {
                    TextField("Default accession / plant ID", text: $settings.defaultAccession)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }

                Section {
                    Toggle("Use cloud shape classification", isOn: $settings.cloudEnabled)
                    if settings.cloudEnabled {
                        SecureField("Anthropic API key (sk-ant-…)", text: $settings.apiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Picker("Model", selection: $settings.model) {
                            Text("Haiku 4.5 — fast & cheap").tag("claude-haiku-4-5-20251001")
                            Text("Sonnet 4.6 — better at shape/ribbing").tag("claude-sonnet-4-6")
                        }
                    }
                } header: {
                    Text("Cloud (hybrid)")
                } footer: {
                    Text("On-device handles size + measurement. When enabled, each clean fruit crop is also sent to Claude, which classifies it into one of the 7 training shapes (round, flat, oval, elongated, heart, pear, fasciated). Off = fully offline with coarse on-device categories. Your key is stored on this device only.")
                }

                Section("Data") {
                    LabeledContent("Total fruit recorded", value: "\(store.measurements.count)")
                    Button("Clear all data", role: .destructive) { showClearConfirm = true }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all recorded measurements?",
                                isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { store.clearAll() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
