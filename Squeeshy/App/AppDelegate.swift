import CloudKit
import UIKit
import UserNotifications

/// UIKit hooks SwiftUI doesn't offer: accepting an iCloud share invitation,
/// and CloudKit's silent pushes when a friend's shelf changes.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            await FriendsStore.shared.handleRemoteNotification()
            completionHandler(.newData)
        }
    }

    /// Show trade notifications even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Invitation tapped while the app was already running.
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in await FriendsStore.shared.accept(cloudKitShareMetadata) }
    }

    /// Invitation tapped while the app was closed.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        Task { @MainActor in await FriendsStore.shared.accept(metadata) }
    }
}
