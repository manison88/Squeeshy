import SwiftUI
import SwiftData
import PhotosUI

/// Shutter, cut-out, rate, name. One squeeshy per capture, and the scale is live the
/// moment the cut-out lands so the whole thing is about six seconds.
struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var allSquishies: [Squishy]

    @State private var camera = CameraController()
    @State private var stage: Stage = .framing
    @State private var pickerItem: PhotosPickerItem?
    @State private var cutout: UIImage?
    @State private var traits: ExtractedTraits?
    @State private var failure: String?

    enum Stage: Equatable { case framing, working, review }

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: reviewTint)

            switch stage {
            case .framing: framing
            case .working: working
            case .review:  review
            }
        }
        .onAppear {
            camera.start()
            #if DEBUG
            if DebugLaunch.captureSample {
                stage = .working
                Task { await process(SampleShot.make()) }
            } else if DebugLaunch.reviewSample {
                let stand = SampleShot.cutout()
                cutout = stand
                traits = SubjectLift.traits(from: stand)
                stage = .review
            }
            #endif
        }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadFromLibrary(item) }
        }
    }

    private var reviewTint: Tint {
        guard let traits else { return .fallback }
        return Tint.single(traits.hue)
    }

    // MARK: Framing

    private var framing: some View {
        ZStack {
            if camera.status == .running {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else {
                unavailableBackdrop
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .frame(width: 38, height: 38)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.tap)
                    Spacer()
                }
                Spacer()

                reticle
                Spacer()

                // The lift is dramatically better when the squeeshy is put down than
                // when it is held up, because a hand in frame is the one thing the
                // segmenter reliably fights with. Worth asking for the good shot.
                if failure == nil {
                    Text("Put it down on something plain if you can")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 12)
                }

                if let failure {
                    Text(failure)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }

                shutterRow
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 26)
        }
    }

    private var unavailableBackdrop: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.ink3)
            Text(camera.status == .denied ? "Camera access is off" : "No camera here")
                .font(.display(19, .semibold))
                .foregroundStyle(Color.ink)
            Text(camera.status == .denied
                 ? "Turn it on in Settings, or pick a photo you already have."
                 : "Pick a photo from your library instead.")
                .font(.system(size: 14))
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    /// Corner brackets rather than a full frame: it suggests where to put the squeeshy
    /// without implying the app will crop to that rectangle.
    private var reticle: some View {
        GeometryReader { geo in
            let inset: CGFloat = 30
            let box = CGRect(x: inset, y: 0, width: geo.size.width - inset * 2, height: geo.size.height)
            Path { p in
                let len: CGFloat = 30, r: CGFloat = 18
                for (corner, dx, dy) in [(box.origin, 1.0, 1.0),
                                         (CGPoint(x: box.maxX, y: box.minY), -1.0, 1.0),
                                         (CGPoint(x: box.minX, y: box.maxY), 1.0, -1.0),
                                         (CGPoint(x: box.maxX, y: box.maxY), -1.0, -1.0)] {
                    p.move(to: CGPoint(x: corner.x + dx * r + dx * len, y: corner.y + dy * 1))
                    p.addLine(to: CGPoint(x: corner.x + dx * r, y: corner.y + dy * 1))
                    p.move(to: CGPoint(x: corner.x + dx * 1, y: corner.y + dy * r + dy * len))
                    p.addLine(to: CGPoint(x: corner.x + dx * 1, y: corner.y + dy * r))
                }
            }
            .stroke(Color.ink2, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .frame(height: 300)
    }

    private var shutterRow: some View {
        HStack {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .frame(width: 50, height: 50)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.tap)

            Spacer()

            Button { shoot() } label: {
                // Always white, never `Color.ink`. This sits on a camera preview, not
                // on the app's ground, so it must not follow the light/dark scheme —
                // an adaptive ink shutter turns near-black in light mode and disappears
                // against whatever the camera happens to be pointing at.
                ZStack {
                    Circle().stroke(.white.opacity(0.9), lineWidth: 4).frame(width: 74, height: 74)
                    Circle().fill(.white).frame(width: 60, height: 60)
                }
            }
            .buttonStyle(ShutterStyle())
            .disabled(camera.status != .running)
            .opacity(camera.status == .running ? 1 : 0.3)

            Spacer()
            Color.clear.frame(width: 50, height: 50)
        }
    }

    // MARK: Working

    private var working: some View {
        ScanIndicator()
    }

    // MARK: Review

    @ViewBuilder
    private var review: some View {
        if let cutout, let traits {
            CaptureReview(cutout: cutout,
                          traits: traits,
                          existing: allSquishies,
                          onSave: { name, score, species, size, duplicateOf in
                              save(name: name, score: score, species: species,
                                   size: size, duplicateOf: duplicateOf, cutout: cutout, traits: traits)
                          },
                          onRetake: { reset() })
        }
    }

    // MARK: Actions

    private func shoot() {
        stage = .working
        camera.capture { image in
            guard let image else {
                fail("That didn't come out. Try again.")
                return
            }
            Task { await process(image) }
        }
    }

    private func loadFromLibrary(_ item: PhotosPickerItem) async {
        stage = .working
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            fail("Couldn't open that photo.")
            return
        }
        await process(image)
    }

    /// How long the scanner stays up even when the lift beats it. Vision usually
    /// finishes in around half a second, which is long enough to notice something
    /// appeared and too short to read it — the result is a flicker between two screens.
    /// Holding here costs a beat and buys a transition that looks deliberate.
    private static let minimumScanTime: TimeInterval = 1.4

    private func process(_ image: UIImage) async {
        let started = Date()
        let lifted = await SubjectLift.cutout(from: image)
        let extracted = lifted.map { SubjectLift.traits(from: $0) }

        // Applies to the failure path too, or a rejected photo snaps back to the
        // viewfinder before you have registered that anything happened.
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < Self.minimumScanTime {
            try? await Task.sleep(for: .seconds(Self.minimumScanTime - elapsed))
        }

        guard let lifted, let extracted else {
            fail("Couldn't find a squeeshy in that. Fill more of the frame and try again.")
            return
        }
        await MainActor.run {
            cutout = lifted
            traits = extracted
            withAnimation(Motion.arrive) { stage = .review }
        }
    }

    private func fail(_ message: String) {
        Task { @MainActor in
            failure = message
            withAnimation(Motion.tap) { stage = .framing }
            pickerItem = nil
        }
    }

    private func reset() {
        cutout = nil
        traits = nil
        failure = nil
        pickerItem = nil
        withAnimation(Motion.tap) { stage = .framing }
    }

    private func save(name: String, score: Double, species: Species, size: SizeClass,
                      duplicateOf: Squishy?, cutout: UIImage, traits: ExtractedTraits) {
        if let original = duplicateOf {
            // Owning two of the same squeeshy is a count, not a second row.
            original.quantity += 1
            try? context.save()
            dismiss()
            return
        }

        let squishy = Squishy(name: name.isEmpty ? "Unnamed" : name,
                              species: species,
                              hue: traits.hue,
                              size: size,
                              squeeshiness: score,
                              typeName: "")
        squishy.saturation = traits.saturation
        squishy.photoFilename = PhotoStore.save(cutout)
        context.insert(squishy)
        try? context.save()
        dismiss()
    }
}

struct ShutterStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
    }
}
