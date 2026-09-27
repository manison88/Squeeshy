import AVFoundation
import SwiftUI

/// The one place UIKit is required. SPEC.md §4.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// iPad: rotate with the device. iPhone: fixed portrait.
    var followsDeviceRotation = false

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if followsDeviceRotation {
            view.attachRotationIfNeeded(to: session)
        } else if view.previewLayer.connection?.isVideoRotationAngleSupported(90) == true {
            view.previewLayer.connection?.videoRotationAngle = 90
        }
        return view
    }

    /// The session's input is added on the session queue, so it may not exist
    /// when the view is made; try again on each update.
    func updateUIView(_ uiView: PreviewView, context: Context) {
        if followsDeviceRotation { uiView.attachRotationIfNeeded(to: session) }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        private var coordinator: AVCaptureDevice.RotationCoordinator?
        private var observation: NSKeyValueObservation?

        func attachRotationIfNeeded(to session: AVCaptureSession) {
            guard coordinator == nil,
                  let device = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first?.device else { return }
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            self.coordinator = coordinator
            previewLayer.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
            observation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview,
                                              options: [.new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                DispatchQueue.main.async {
                    self?.previewLayer.connection?.videoRotationAngle = angle
                }
            }
        }
    }
}
