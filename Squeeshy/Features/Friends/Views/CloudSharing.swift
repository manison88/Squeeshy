import CloudKit
import UIKit

/// Presents the system invite sheet for this user's shelf. UIKit, because
/// `UICloudSharingController` is the one reliable way to invite people to an
/// existing share and manage who is on it.
@MainActor
enum CloudSharing {
    private static var delegate: Delegate?

    /// Returns false when there was nowhere to present from, so the caller can
    /// say so instead of doing nothing.
    @discardableResult
    static func present(share: CKShare, container: CKContainer, title: String) -> Bool {
        guard let presenter = topViewController() else { return false }
        let controller = UICloudSharingController(share: share, container: container)
        // Private invitations, read-only: friends can look, never edit.
        controller.availablePermissions = [.allowPrivate, .allowReadOnly]
        let delegate = Delegate(title: title)
        Self.delegate = delegate
        controller.delegate = delegate
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY - 80,
                                        width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
        return true
    }

    /// Opens the invite sheet for this user's shelf, or explains on the Friends
    /// screen why it couldn't. Every route to "Add a friend" goes through here.
    static func invite(store: FriendsStore) async {
        do {
            let share = try await store.shareForInvite()
            // A sheet that is still animating away (the name sheet, an alert) leaves
            // nothing to present from, so give it a moment and try once more.
            let title = "\(store.displayName)'s squeeshies"
            if !present(share: share, container: store.container, title: title) {
                try? await Task.sleep(for: .seconds(0.6))
                if !present(share: share, container: store.container, title: title) {
                    store.report("Couldn't open the invite screen. Try Add a friend again.")
                }
            }
        } catch {
            store.report(error)
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
            ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        // Presenting from something mid-dismissal silently does nothing.
        if top?.isBeingDismissed == true || top?.presentedViewController != nil { return nil }
        return top
    }

    private final class Delegate: NSObject, UICloudSharingControllerDelegate {
        let title: String
        init(title: String) { self.title = title }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            Task { @MainActor in
                FriendsStore.shared.report(error)
                await FriendsStore.shared.refresh()
            }
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            Task { @MainActor in await FriendsStore.shared.refresh() }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in await FriendsStore.shared.start() }
        }
    }
}
