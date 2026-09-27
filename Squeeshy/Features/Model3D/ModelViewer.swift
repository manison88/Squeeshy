import SwiftUI
import SceneKit
import GLTFKit2

/// A squeeshy you can actually turn over.
///
/// The mesh comes back from the generator as a glTF binary; SceneKit cannot read
/// those, so GLTFKit2 does the import and hands back a scene. Rendered with SceneKit
/// rather than RealityKit because RealityKit wants USDZ and a conversion step on the
/// way in would mean either a server round trip or a second toolchain.
struct ModelViewer: View {
    /// Absolute path to a .glb on disk.
    var url: URL
    var tint: Color

    @State private var scene: SCNScene?
    @State private var failed = false
    @State private var spin: Double = 0
    @State private var dragging = false

    var body: some View {
        ZStack {
            if let scene {
                // SwiftUI's SceneView paints an opaque background and ignores a
                // camera node in the scene, so the view is wrapped directly.
                TransparentSceneView(scene: scene)
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Color.ink3)
                    MetaLabel(text: "couldn't open that model")
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        failed = false
        scene = nil
        do {
            let asset = try await GLTFAsset(url: url)
            let source = GLTFSCNSceneSource(asset: asset)
            guard let built = source.defaultScene else { failed = true; return }
            decorate(built)
            scene = built
        } catch {
            failed = true
        }
    }

    /// Lighting and framing the generator does not provide. Three lights rather than
    /// SceneKit's default one, because a single lamp on a matte blob reads flat —
    /// the same problem the relief prototype had.
    private func decorate(_ scene: SCNScene) {
        scene.background.contents = UIColor.clear

        let key = SCNLight()
        key.type = .directional
        key.intensity = 780
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 8
        key.shadowColor = UIColor.black.withAlphaComponent(0.35)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.7, 0.6, 0)
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 320
        fill.color = UIColor(tint)
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(0.3, -1.1, 0)
        scene.rootNode.addChildNode(fillNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 260
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Frame the model regardless of the scale the generator chose.
        let (minV, maxV) = scene.rootNode.boundingBox
        let size = max(maxV.x - minV.x, max(maxV.y - minV.y, maxV.z - minV.z))
        if size > 0 {
            let target = 1.0 / size
            scene.rootNode.scale = SCNVector3(target, target, target)
        }

        let camera = SCNCamera()
        camera.usesOrthographicProjection = false
        camera.fieldOfView = 32
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 3.4)
        scene.rootNode.addChildNode(cameraNode)

        // A slow idle turn, so a card that is just sitting there still reads as solid.
        let turn = SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 18)
        )
        scene.rootNode.runAction(turn)
    }
}

/// SCNView with a clear background, so the squeeshy floats on the app's own ground
/// instead of arriving in a white box. Also uses the camera the scene provides,
/// which SwiftUI's SceneView discards.
private struct TransparentSceneView: UIViewRepresentable {
    var scene: SCNScene

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.rendersContinuously = true
        view.pointOfView = scene.rootNode.childNodes.first { $0.camera != nil }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene !== scene {
            view.scene = scene
            view.pointOfView = scene.rootNode.childNodes.first { $0.camera != nil }
        }
    }
}

// MARK: - Storage

extension PhotoStore {
    /// Meshes live beside the cut-outs, and go to R2 the same way when that lands.
    static func modelURL(for filename: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base.appendingPathComponent(filename)
    }

    static func hasModel(_ filename: String?) -> Bool {
        guard let filename else { return false }
        return FileManager.default.fileExists(atPath: modelURL(for: filename).path)
    }
}

#if DEBUG
/// Loads the stand-in mesh bundled for development, so the viewer can be worked on
/// without spending generator quota.
struct ModelViewerPreviewHarness: View {
    var body: some View {
        ZStack {
            AdaptiveBackground(tint: .fallback)
            if let url = Bundle.main.url(forResource: "mesh_test", withExtension: "glb") {
                ModelViewer(url: url, tint: Tint.fallback.primary)
            } else {
                Text("mesh_test.glb missing from the bundle")
                    .foregroundStyle(Color.ink)
            }
        }
    }
}
#endif
