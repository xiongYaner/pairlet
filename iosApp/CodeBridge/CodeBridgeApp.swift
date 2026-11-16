import SwiftUI
import ComposeApp
import UserNotifications

@main
struct CodeBridgeApp: App {
    @UIApplicationDelegateAdaptor(CodeBridgeAppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = BridgeStore()

    var body: some Scene {
        WindowGroup {
            CodeBridgeRoot(store: store)
                .tint(Color(red: 0.86, green: 0.48, blue: 0.34))
                .onOpenURL { MainViewControllerKt.handleDeepLink(url: $0.absoluteString) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.runtime.foreground()
                        delegate.refreshToken()
                    } else if phase == .background {
                        store.runtime.background()
                    }
                }
        }
    }
}

final class CodeBridgeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        MainViewControllerKt.setPushRegistrar { [weak self] prompt in
            if prompt.boolValue {
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    DispatchQueue.main.async {
                        if granted {
                            PushController.shared.registrationStarted()
                            application.registerForRemoteNotifications()
                        } else {
                            PushController.shared.registrationFailed(category: 2)
                        }
                    }
                }
            } else { self?.refreshToken() }
        }
        MainViewControllerKt.setPushAuthorizationReader { reply in
            center.getNotificationSettings { settings in
                DispatchQueue.main.async { _ = reply(KotlinInt(int: Int32(settings.authorizationStatus.rawValue))) }
            }
        }
        MainViewControllerKt.setPushSettingsOpener {
            DispatchQueue.main.async {
                guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                application.open(url)
            }
        }
        MainViewControllerKt.setPushDismisser { sessionId in
            center.getDeliveredNotifications { notifications in
                center.removeDeliveredNotifications(withIdentifiers: notifications.filter {
                    ($0.request.content.userInfo["sid"] as? String) == sessionId
                }.map(\.request.identifier))
            }
        }
        refreshToken()
        return true
    }

    func refreshToken() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
            DispatchQueue.main.async {
                PushController.shared.registrationStarted()
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if DEBUG
        let platform = "apns_sandbox"
        #else
        let platform = "apns"
        #endif
        MainViewControllerKt.setPushToken(platform: platform, token: deviceToken.map { String(format: "%02x", $0) }.joined())
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushController.shared.registrationFailed(category: 0)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler complete: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        DispatchQueue.main.async { NotificationArchive.shared.record(notification) }
        let present = MainViewControllerKt.shouldPresentPush(sessionId: info["sid"] as? String, kind: info["kind"] as? String)
        complete(present ? [.banner, .sound, .badge] : [])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler complete: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        DispatchQueue.main.async { NotificationArchive.shared.record(response.notification, read: true) }
        if let path = info["wd"] as? String, let sessionId = info["sid"] as? String {
            DispatchQueue.main.async { MainViewControllerKt.handlePushOpen(workdir: path, sessionId: sessionId) }
        }
        complete()
    }
}
