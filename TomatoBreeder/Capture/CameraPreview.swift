import SwiftUI
import ARKit

/// Embeds the controller's ARSCNView so the live camera feed shows on screen,
/// and keeps the controller's viewport size in sync so detection overlays align.
struct CameraPreview: UIViewRepresentable {
    let controller: ARCaptureController

    func makeUIView(context: Context) -> ARSCNView {
        let view = controller.sceneView
        view.automaticallyUpdatesLighting = true
        view.contentMode = .scaleAspectFill
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        let size = uiView.bounds.size
        if size.width > 0, size.height > 0 {
            controller.viewportSize = size
        }
    }
}
