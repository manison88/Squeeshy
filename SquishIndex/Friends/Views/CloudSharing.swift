import CloudKit
import UIKit

/// Presents the system invite sheet for this user's shelf. UIKit, because
/// `UICloudSharingController` is the one reliable way to invite people to an
/// existing share and manage who is on it.
@MainActor
enum CloudSharing {
    private static var delegate: Delegate?

    static func present(share: CKShare, container: CKContainer, title: String) {
        guard let presenter = topViewController() else { return }
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
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private final class Delegate: NSObject, UICloudSharingControllerDelegate {
        let title: String
        init(title: String) { self.title = title }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            Task { @MainActor in await FriendsStore.shared.refresh() }
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            Task { @MainActor in await FriendsStore.shared.refresh() }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in await FriendsStore.shared.start() }
        }
    }
}
