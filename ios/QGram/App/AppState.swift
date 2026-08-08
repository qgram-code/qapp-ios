import SwiftUI

/// Global session + cross-screen state (counters, presence, toasts).
@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case launching
        case signedOut
        case signedIn
        /// Account is banned / frozen / restricted — the API refuses everything.
        case restricted(String)
    }

    @Published private(set) var phase: Phase = .launching
    @Published private(set) var me: QUser?
    @Published private(set) var unreadChats: Int = 0
    @Published private(set) var unreadNotifications: Int = 0
    @Published var toast: QToast?

    /// Status the heartbeat keeps publishing. Chosen by the user in settings and
    /// remembered between launches (the server forgets it after 75 s of silence).
    @Published private(set) var presenceStatus: QPresence = {
        QPresence(rawValue: UserDefaults.standard.string(forKey: "qgram.presence") ?? "") ?? .online
    }()

    /// Bumped whenever a post is created or deleted so the feed and the profile
    /// can refresh without knowing about each other.
    @Published private(set) var contentRevision: Int = 0

    private let api = APIClient.shared
    private var heartbeatTask: Task<Void, Never>?
    private var countersTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(
            NotificationCenter.default.addObserver(forName: .qgramUnauthorized, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleUnauthorized() }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(forName: .qgramAccountRestricted, object: nil, queue: .main) { [weak self] note in
                // `Notification` is not Sendable — unwrap before hopping actors.
                guard let error = note.object as? APIError else { return }
                Task { @MainActor in
                    self?.handleRestriction(error)
                }
            }
        )
    }

    // MARK: - Session

    func bootstrap() async {
        guard let token = TokenStore.load() else {
            phase = .signedOut
            return
        }
        await api.setToken(token)
        do {
            let user = try await api.me()
            me = user
            phase = .signedIn
            startBackgroundWork()
            PushManager.shared.onSignIn()
        } catch let error as APIError {
            if error == .unauthorized {
                await clearSession()
            } else if error.isAccountRestriction {
                handleRestriction(error)
            } else {
                // Offline launch: keep the token and let each screen retry.
                phase = .signedIn
                startBackgroundWork()
            }
        } catch {
            phase = .signedIn
            startBackgroundWork()
        }
    }

    func signIn(user: QUser, token: String) async {
        TokenStore.save(token)
        TokenStore.lastUsername = user.username
        await api.setToken(token)
        me = user
        phase = .signedIn
        startBackgroundWork()
        PushManager.shared.onSignIn()
        await refreshCounters()
    }

    func signOut() async {
        stopBackgroundWork()
        await PushManager.shared.onSignOut()
        _ = try? await api.setPresence(.offline)
        await api.logout()
        await clearSession()
    }

    private func clearSession() async {
        TokenStore.clear()
        await api.setToken(nil)
        me = nil
        unreadChats = 0
        unreadNotifications = 0
        phase = .signedOut
    }

    private func handleUnauthorized() {
        guard phase != .signedOut else { return }
        Task { await clearSession() }
        toast = QToast(kind: .error, text: "Сессия истекла — войдите снова")
    }

    private func handleRestriction(_ error: APIError) {
        stopBackgroundWork()
        phase = .restricted(error.userMessage)
    }

    func leaveRestrictedScreen() async {
        await clearSession()
    }

    func refreshMe() async {
        guard phase == .signedIn else { return }
        if let user = try? await api.me() {
            me = user
        }
    }

    func updateMe(_ user: QUser) {
        me = user
    }

    func contentChanged() {
        contentRevision &+= 1
    }

    func show(_ toast: QToast) {
        self.toast = toast
    }

    func showError(_ error: Error) {
        if error is CancellationError { return }
        let message = (error as? APIError)?.userMessage ?? error.localizedDescription
        toast = QToast(kind: .error, text: message)
    }

    // MARK: - Counters & presence

    func refreshCounters() async {
        guard phase == .signedIn else { return }
        async let chatsRequest = api.unreadChats()
        async let notificationsRequest = api.unreadNotifications()
        let chats = try? await chatsRequest
        let notifications = try? await notificationsRequest
        if let chats { unreadChats = chats }
        if let notifications { unreadNotifications = notifications }
        PushManager.shared.updateBadge(unreadChats + unreadNotifications)
    }

    func setUnreadChats(_ value: Int) {
        unreadChats = max(0, value)
    }

    func updatePresence(_ status: QPresence) async {
        presenceStatus = status
        UserDefaults.standard.set(status.rawValue, forKey: "qgram.presence")
        _ = try? await APIClient.shared.setPresence(status)
    }

    func startBackgroundWork() {
        guard phase == .signedIn else { return }
        if heartbeatTask == nil {
            heartbeatTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let status = self.presenceStatus
                    _ = try? await APIClient.shared.setPresence(status)
                    try? await Task.sleep(nanoseconds: AppConfig.presenceHeartbeatInterval * 1_000_000_000)
                }
            }
        }
        if countersTask == nil {
            countersTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refreshCounters()
                    try? await Task.sleep(nanoseconds: AppConfig.countersPollInterval * 1_000_000_000)
                }
            }
        }
    }

    func stopBackgroundWork() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        countersTask?.cancel()
        countersTask = nil
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            startBackgroundWork()
            Task { await refreshCounters() }
        case .background:
            stopBackgroundWork()
            Task { _ = try? await APIClient.shared.setPresence(.offline) }
        default:
            break
        }
    }
}
