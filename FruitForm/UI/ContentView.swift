import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            CaptureView()
                .tabItem { Label("Capture", systemImage: "camera.viewfinder") }
            ResultsView()
                .tabItem { Label("Results", systemImage: "list.bullet.rectangle") }
            TrainingView()
                .tabItem { Label("Training", systemImage: "square.stack.3d.up.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
