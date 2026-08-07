import Foundation

/// Everything environment-specific lives here so a build can be pointed at a
/// staging host without touching feature code.
enum AppConfig {
    static let baseURL = URL(string: "https://qgram.fun")!

    static let websiteURL = URL(string: "https://qgram.fun")!

    static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    /// The server pushes mobile *browsers* to the installed app, so the client
    /// identifies itself explicitly instead of inheriting the CFNetwork agent.
    static var userAgent: String {
        "QGramiOS/\(appVersion) (iOS)"
    }

    // MARK: - Limits mirrored from the backend

    static let postMaxImagesFree = 3
    static let postMaxImagesPremium = 5
    static let postMaxMBFree = 10
    static let postMaxMBPremium = 20
    static let bioMaxLength = 500
    /// `AVATAR_MAX_MB` / `BANNER_MAX_MB` in app.py — the banner limit is 5 MB,
    /// not the 8 MB the written docs claim.
    static let avatarMaxMB = 5
    static let bannerMaxMB = 5
    static let chatAttachmentMaxMB = 10
    static let chatAttachmentsPerMessage = 10
    static let commentMaxLength = 4000

    // MARK: - Polling intervals (seconds)

    static let chatPollInterval: UInt64 = 3
    static let chatsListPollInterval: UInt64 = 10
    static let countersPollInterval: UInt64 = 30
    static let presenceHeartbeatInterval: UInt64 = 45
    static let typingPingInterval: TimeInterval = 4

    /// The messages endpoint only returns the newest page when `before_id` is
    /// present; without it the server walks messages from the oldest id up.
    /// A sentinel above any realistic message id gives us "latest N".
    static let latestMessagesSentinelID = 2_147_483_647
}
