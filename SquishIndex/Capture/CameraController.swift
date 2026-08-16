import AVFoundation
import CoreImage
import Observation
import UIKit
import Vision

/// The capture session. Portrait only, depth on when the hardware has it, and
/// the measurement method it will be able to offer is known before the shutter
/// is pressed — SPEC.md §4 requires the method always be surfaced.
@Observable
final class CameraController: NSObject, @unchecked Sendable {

    enum Status: Equatable {
        case idle
        case notDetermined
        case denied
        case unavailable
        case running
        case interrupted
    }

    private(set) var status: Status = .idle
    private(set) var method: MeasurementMethod = .none
    /// Normalised, origin top-left, in the upright preview frame.
    private(set) var subjectBox: CGRect?
    private(set) var isCapturing = false
    private(set) var failureMessage: String?

    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "index.squish.camera.session")
    private let visionQueue = DispatchQueue(label: "index.squish.camera.vision")
    private var device: AVCaptureDevice?
    private var completion: (@MainActor (SquishyVision.Sample?) -> Void)?
    private var lastVisionRun = Date.distantPast
    private var isConfigured = false

    // MARK: Lifecycle

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            setStatus(.notDetermined)
        case .denied, .restricted:
            setStatus(.denied)
        @unknown default:
            setStatus(.denied)
        }
    }

    func requestAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            granted ? self.configureAndRun() : self.setStatus(.denied)
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                guard self.configure() else {
                    self.setStatus(.unavailable)
                    return
                }
                self.isConfigured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
            self.setStatus(.running)
            self.observeInterruptions()
        }
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        // The measurement ladder, resolved in hardware order.
        let discovered = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInLiDARDepthCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        ).devices
        guard let device = discovered.first,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        self.device = device

        guard session.canAddOutput(photoOutput) else { return false }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        var resolvedMethod = MeasurementMethod.none
        if photoOutput.isDepthDataDeliverySupported {
            photoOutput.isDepthDataDeliveryEnabled = true
            resolvedMethod = device.deviceType == .builtInLiDARDepthCamera ? .lidar : .depth
        }
        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
            session.addOutput(videoOutput)
        }

        // Portrait, once, on every connection — then every buffer, the photo
        // and the depth map all share one upright frame.
        for output in [photoOutput as AVCaptureOutput, videoOutput as AVCaptureOutput] {
            guard let connection = output.connection(with: .video) else { continue }
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }

        setMethod(resolvedMethod)
        return true
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main
        ) { [weak self] _ in self?.setStatus(.interrupted) }
        NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main
        ) { [weak self] _ in self?.setStatus(.running) }
    }

    // MARK: Capture

    func capture(completion: @escaping @MainActor (SquishyVision.Sample?) -> Void) {
        self.completion = completion
        setCapturing(true)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            if self.photoOutput.isDepthDataDeliveryEnabled {
                settings.isDepthDataDeliveryEnabled = true
                settings.embedsDepthDataInPhoto = false
                settings.isCameraCalibrationDataDeliveryEnabled =
                    self.photoOutput.isCameraCalibrationDataDeliverySupported
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func focus(atNormalisedPoint point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let device = self?.device, device.isFocusPointOfInterestSupported else { return }
            try? device.lockForConfiguration()
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        }
    }

    /// A still imported from the library gets the same pipeline, minus depth.
    static func sample(from image: UIImage) -> SquishyVision.Sample? {
        guard let cg = image.normalisedUp()?.cgImage else { return nil }
        return SquishyVision.Sample(image: cg, depth: nil, fieldOfViewDegrees: nil, isLiDAR: false)
    }

    // MARK: State plumbing

    private func setStatus(_ new: Status) {
        Task { @MainActor in self.status = new }
    }

    private func setMethod(_ new: MeasurementMethod) {
        Task { @MainActor in self.method = new }
    }

    private func setCapturing(_ new: Bool) {
        Task { @MainActor in self.isCapturing = new }
    }

    private func setSubjectBox(_ new: CGRect?) {
        Task { @MainActor in self.subjectBox = new }
    }

    func clearFailure() {
        failureMessage = nil
    }

    private func report(_ message: String?) {
        Task { @MainActor in self.failureMessage = message }
    }
}

// MARK: - Photo delegate

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        setCapturing(false)
        guard error == nil, let cgImage = photo.cgImageRepresentation() else {
            report("Capture failed · try again")
            deliver(nil)
            return
        }

        // The connection is already rotated to portrait, so the frame is
        // upright; anything else in the metadata is applied to the depth map so
        // the two stay in step.
        var depth = photo.depthData
        if let orientationValue = photo.metadata[kCGImagePropertyOrientation as String] as? UInt32,
           let orientation = CGImagePropertyOrientation(rawValue: orientationValue),
           orientation != .up {
            depth = depth?.applyingExifOrientation(orientation)
        }

        let sample = SquishyVision.Sample(
            image: cgImage,
            depth: depth,
            fieldOfViewDegrees: device.map { Double($0.activeFormat.videoFieldOfView) },
            isLiDAR: device?.deviceType == .builtInLiDARDepthCamera
        )
        deliver(sample)
    }

    private func deliver(_ sample: SquishyVision.Sample?) {
        let handler = completion
        completion = nil
        Task { @MainActor in handler?(sample) }
    }
}

// MARK: - Live subject lock

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Five looks a second is enough to track a toy on a table, and it keeps
        // the preview at full frame rate.
        guard Date().timeIntervalSince(lastVisionRun) > 0.2,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastVisionRun = Date()

        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let salient = observation.salientObjects?.first else {
            setSubjectBox(nil)
            return
        }
        // Vision's origin is bottom-left; everything downstream is top-left.
        let box = salient.boundingBox
        setSubjectBox(CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
    }
}

// MARK: - Orientation

extension UIImage {
    /// Redraws the image so its pixels are upright and `imageOrientation` is
    /// `.up` — Vision and Core Image both read pixels, not metadata.
    func normalisedUp() -> UIImage? {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
