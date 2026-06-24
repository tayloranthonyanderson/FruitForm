import SwiftUI

@main
struct FruitFormApp: App {
    @StateObject private var store = MeasurementStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var trainingStore = TrainingStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(trainingStore)
        }
    }
}
