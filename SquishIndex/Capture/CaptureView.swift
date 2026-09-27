import AVFoundation
import PhotosUI
import SwiftUI

/// Screen 3 — viewfinder.
///
/// The canvas here is `ink`, not `putty`: throwing a light surface around a
/// camera preview shifts how the subject's exposure reads.
@MainActor
struct CaptureView: View {
    @Bindable var flow: CaptureFlow
    let onClose: () -> Void

    @State private var camera = CameraController()
    /// iPad rotates freely, so the camera follows it; iPhone stays portrait.
    private let isPad = UIDevice.current.userInterfaceIdiom == .pad
    @State private var focusPoint: CGPoint?
    @State private var focusToken = 0
    @State private var pickerItem: PhotosPickerItem?
    @State private var captureCount = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SquishTheme.ink.ignoresSafeArea()

            switch camera.status {
            case .running, .interrupted:
                preview
            case .notDetermined:
                permissionBlock(
                    message: "Squish Index needs the camera to photograph and measure specimens. Photos stay on this device.",
                    action: "Allow camera"
                ) { camera.requestAccess() }
            case .denied:
                permissionBlock(
                    message: "Camera access is off for Squish Index. You can turn it on in Settings.",
                    action: "Open Settings"
                ) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            case .unavailable:
                permissionBlock(message: "This device has no camera.", action: "Choose from library") {}
            case .idle:
                Color.clear
            }

            overlay
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            camera.followsDeviceRotation = isPad
            camera.start()
        }
        .onDisappear { camera.stop() }
        .sensoryFeedback(.impact(weight: .medium), trigger: captureCount)
        .task(id: pickerItem) { await loadPickedItem() }
    }

    // MARK: Preview

    private var preview: some View {
        GeometryReader { proxy in
            CameraPreview(session: camera.session, followsDeviceRotation: isPad)
                .ignoresSafeArea()
                .opacity(camera.status == .interrupted ? 0.4 : 1)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    focusPoint = location
                    focusToken += 1
                    camera.focus(atNormalisedPoint: CGPoint(x: location.y / proxy.size.height,
                                                            y: 1 - location.x / proxy.size.width))
                }
                .overlay {
                    if let focusPoint {
                        FocusSquare(token: focusToken)
                            .position(focusPoint)
                            .accessibilityHidden(true)
                    }
                }
        }
    }

    // MARK: Overlay chrome

    private var overlay: some View {
        VStack(spacing: 0) {
            topBand
            Spacer(minLength: 0)
            brackets
            Spacer(minLength: 0)
            bottomBand
        }
        .opacity(camera.status == .interrupted ? 0.4 : 1)
        .animation(SquishTheme.Motion.readout, value: camera.status)
    }

    private var topBand: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(SquishTheme.chalk)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close capture")

            Spacer()

            MethodBadge(method: camera.method)
        }
        .padding(.horizontal, SquishTheme.Space.margin)
        .padding(.top, SquishTheme.Space.gutter)
    }

    private var brackets: some View {
        VStack(spacing: SquishTheme.Space.gutter) {
            GeometryReader { proxy in
                let box = bracketRect(in: proxy.size)
                CornerBrackets()
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)
                    .animation(reduceMotion ? nil : SquishTheme.Motion.surface, value: camera.subjectBox)
                    .accessibilityHidden(true)
            }
            .frame(height: 300)

            Text(lockReadout)
                .typeStyle(.m1)
                .foregroundStyle(SquishTheme.chalk)
                .monospacedDigit()
                .id(lockReadout)
                .transition(.opacity)
                .animation(SquishTheme.Motion.readout, value: lockReadout)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var bottomBand: some View {
        ZStack {
            if let failure = camera.failureMessage {
                MonoLabel(text: failure, tint: SquishTheme.chalk)
                    .padding(.horizontal, SquishTheme.Space.gutter)
                    .padding(.vertical, SquishTheme.Space.sm)
                    .background(SquishTheme.ink.opacity(0.7), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        camera.clearFailure()
                    }
            }

            HStack {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20))
                        .foregroundStyle(SquishTheme.chalk)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Choose from library")

                Spacer()

                ShutterButton(isBusy: camera.isCapturing) { shoot() }

                Spacer()

                // The reference-card path needs no control of its own: any card
                // lying beside the toy is picked up automatically. A dead
                // button would be worse than an asymmetric bar.
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, SquishTheme.Space.margin)
        }
        .frame(height: 132)
        .animation(SquishTheme.Motion.readout, value: camera.failureMessage)
    }

    // MARK: Pieces

    private func permissionBlock(message: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: SquishTheme.Space.gutter) {
            Eyebrow("Camera", tint: SquishTheme.chalk.opacity(0.7))
            Text(message)
                .typeStyle(.b1)
                .foregroundStyle(SquishTheme.chalk)
            Button(action: perform) {
                Text(action)
                    .typeStyle(.b2)
                    .foregroundStyle(SquishTheme.ink)
                    .padding(.horizontal, SquishTheme.Space.margin)
                    .frame(height: 44)
                    .background(SquishTheme.chalk, in: Capsule())
            }
            .padding(.top, SquishTheme.Space.sm)
        }
        .frame(maxWidth: 320, alignment: .leading)
        .padding(SquishTheme.Space.margin)
    }

    private var lockReadout: String {
        switch camera.status {
        case .interrupted: return "Paused"
        default: break
        }
        guard camera.subjectBox != nil else { return "Searching" }
        return camera.method.capturesSize ? "Subject locked · \(camera.method.badgeText)" : "Subject locked"
    }

    private func bracketRect(in size: CGSize) -> CGRect {
        guard let box = camera.subjectBox else {
            let side = min(260, min(size.width, size.height))
            return CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2,
                          width: side, height: side)
        }
        let inset: CGFloat = 8
        let rect = CGRect(x: box.minX * size.width - inset,
                          y: box.minY * size.height - inset,
                          width: box.width * size.width + inset * 2,
                          height: box.height * size.height + inset * 2)
        return rect.intersection(CGRect(origin: .zero, size: size))
    }

    private func shoot() {
        captureCount += 1
        camera.capture { sample in
            guard let sample else { return }
            flow.begin(with: sample)
        }
    }

    private func loadPickedItem() async {
        guard let pickerItem else { return }
        guard let data = try? await pickerItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let sample = CameraController.sample(from: image) else { return }
        flow.begin(with: sample)
        self.pickerItem = nil
    }
}

// MARK: - Method badge

struct MethodBadge: View {
    let method: MeasurementMethod
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Text(method.badgeText)
            .typeStyle(.m1)
            .foregroundStyle(SquishTheme.chalk)
            .padding(.horizontal, SquishTheme.Space.gutter)
            .frame(height: 28)
            .background(
                Capsule().fill(reduceTransparency ? SquishTheme.ink : SquishTheme.chalk.opacity(0.12))
            )
            .overlay(
                Capsule().strokeBorder(SquishTheme.chalk.opacity(reduceTransparency ? 1 : 0.24),
                                       lineWidth: SquishTheme.hairline)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Measurement method")
            .accessibilityValue(method.badgeText)
    }
}

// MARK: - Brackets, shutter, focus

struct CornerBrackets: View {
    var arm: CGFloat = 26
    var stroke: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { path in
                // Top-leading
                path.move(to: CGPoint(x: 0, y: arm)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: arm, y: 0))
                // Top-trailing
                path.move(to: CGPoint(x: w - arm, y: 0)); path.addLine(to: CGPoint(x: w, y: 0)); path.addLine(to: CGPoint(x: w, y: arm))
                // Bottom-trailing
                path.move(to: CGPoint(x: w, y: h - arm)); path.addLine(to: CGPoint(x: w, y: h)); path.addLine(to: CGPoint(x: w - arm, y: h))
                // Bottom-leading
                path.move(to: CGPoint(x: arm, y: h)); path.addLine(to: CGPoint(x: 0, y: h)); path.addLine(to: CGPoint(x: 0, y: h - arm))
            }
            .stroke(SquishTheme.chalk.opacity(0.9),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
        }
    }
}

struct ShutterButton: View {
    var isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(SquishTheme.chalk, lineWidth: 2).frame(width: 74, height: 74)
                Circle().fill(SquishTheme.chalk).frame(width: 62, height: 62)
                    .scaleEffect(isBusy ? 0.86 : 1)
                    .animation(.easeOut(duration: 0.08), value: isBusy)
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Capture")
    }
}

private struct FocusSquare: View {
    let token: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true
    @State private var scale: CGFloat = 1.10

    var body: some View {
        Rectangle()
            .strokeBorder(SquishTheme.chalk, lineWidth: SquishTheme.hairline)
            .frame(width: 62, height: 62)
            .scaleEffect(reduceMotion ? 1 : scale)
            .opacity(visible ? 1 : 0)
            .task(id: token) {
                visible = true
                scale = 1.10
                withAnimation(.easeOut(duration: 0.20)) { scale = 1 }
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(SquishTheme.Motion.dismiss) { visible = false }
            }
    }
}
