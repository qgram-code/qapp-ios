import SwiftUI
import UIKit
import UserNotifications

/// Registers the device with APNs and hands the token to the backend.
///
/// Delivery itself is a server-side concern: `/api/push/devices` answers with
/// `delivery_enabled`, which is false until the APNS_* keys are configured on
/// qgram.fun. The client side is complete either way — tokens are stored and
/// removed with the session.
@MainActor
final class PushManager: NSObject, ObservableObject {
    static let shared = PushManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String?
    @Published private(set) var deliveryEnabled = false

    private var isSignedIn = false

    private var isSandboxBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Called after sign-in: asks once, then keeps the token in sync.
    func onSignIn() {
        isSignedIn = true
        Task {
            await refreshStatus()
            if authorizationStatus == .notDetermined {
                await requestAuthorization()
            } else if let deviceToken {
                await sendToServer(token: deviceToken)
            }
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            await refreshStatus()
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            return false
        }
    }

    func onSignOut() async {
        isSignedIn = false
        if let deviceToken {
            try? await APIClient.shared.removePushDevice(token: deviceToken)
        }
        deliveryEnabled = false
        UIApplication.shared.applicationIconBadgeNumber = 0
    }

    func didRegister(tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        guard isSignedIn else { return }
        Task { await sendToServer(token: token) }
    }

    func didFailToRegister(error: Error) {
        // A simulator or a build without the push entitlement lands here; the
        // rest of the app must keep working.
        deviceToken = nil
        deliveryEnabled = false
    }

    private func sendToServer(token: String) async {
        do {
            deliveryEnabled = try await APIClient.shared.registerPushDevice(token: token, sandbox: isSandboxBuild)
        } catch {
            deliveryEnabled = false
        }
    }

    func updateBadge(_ count: Int) {
        UIApplication.shared.applicationIconBadgeNumber = max(0, count)
    }
}

extension PushManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

/// Minimal app delegate: APNs callbacks are only delivered through UIKit.
final class QGramAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { @MainActor in
            PushManager.shared.configure()
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushManager.shared.didRegister(tokenData: deviceToken)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            PushManager.shared.didFailToRegister(error: error)
        }
    }
}
