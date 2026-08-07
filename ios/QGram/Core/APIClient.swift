import Foundation

extension Notification.Name {
    /// Posted when the server rejects the stored token; `AppState` signs out.
    static let qgramUnauthorized = Notification.Name("qgram.unauthorized")
    /// Posted with an `APIError` payload when the account itself is restricted.
    static let qgramAccountRestricted = Notification.Name("qgram.accountRestricted")
}

enum LoginOutcome {
    case success(QLoginResponse)
    case twoFactorRequired(TwoFactorChallenge)
}

/// Thin, typed wrapper over the QGram HTTP API (see `API_USAGE.txt`).
///
/// It is an `actor` so the bearer token can be mutated from anywhere without
/// data races; every call site is `await`-ed anyway.
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private var token: String?

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 60
            configuration.waitsForConnectivity = true
            configuration.httpAdditionalHeaders = ["User-Agent": AppConfig.userAgent]
            // The bearer token is the only credential this client uses. Keeping
            // cookies would additionally carry a browser session, which the
            // server treats under different (CSRF-protected) rules.
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            self.session = URLSession(configuration: configuration)
        }
    }

    func setToken(_ value: String?) {
        token = value?.isEmpty == true ? nil : value
    }

    func currentToken() -> String? { token }

    // MARK: - Request plumbing

    private enum Body {
        case none
        case json([String: Any])
        case multipart(MultipartBody)
    }

    private struct Request {
        var method: String
        var path: String
        var query: [String: String] = [:]
        var body: Body = .none
        /// Login endpoints must not trigger a global sign-out on 401.
        var emitsAuthEvents: Bool = true
    }

    private func makeURLRequest(_ request: Request) throws -> URLRequest {
        // The path is assembled by hand: `appendingPathComponent` would
        // percent-encode already-escaped segments a second time.
        var base = AppConfig.baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let path = request.path.hasPrefix("/") ? String(request.path.dropFirst()) : request.path
        guard var components = URLComponents(string: base + "/" + path) else {
            throw APIError.network("Некорректный адрес запроса")
        }
        if !request.query.isEmpty {
            components.queryItems = request.query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.network("Некорректный адрес запроса") }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
        if let token {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        switch request.body {
        case .none:
            break
        case .json(let payload):
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        case .multipart(let multipart):
            urlRequest.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = multipart.finalized
        }
        return urlRequest
    }

    private struct RawResponse {
        let data: Data
        let status: Int
        let payload: [String: Any]?
        let retryAfter: Int?

        var apiCode: String { (payload?["error"] as? String) ?? "" }
        var apiMessage: String { (payload?["message"] as? String) ?? "" }
        var ok: Bool? { payload?["ok"] as? Bool }
    }

    /// Performs the HTTP call and parses the envelope without applying any error
    /// policy — used by both `perform` and the login flow, which needs to read a
    /// 401 body instead of treating it as a failure.
    private func execute(_ request: Request) async throws -> RawResponse {
        let urlRequest = try makeURLRequest(request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw APIError.network(Self.message(for: error))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        let http = response as? HTTPURLResponse
        return RawResponse(
            data: data,
            status: http?.statusCode ?? 0,
            payload: (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            retryAfter: Int(http?.value(forHTTPHeaderField: "Retry-After") ?? "")
        )
    }

    @discardableResult
    private func perform(_ request: Request) async throws -> Data {
        let raw = try await execute(request)
        let status = raw.status
        let apiCode = raw.apiCode
        let apiMessage = raw.apiMessage
        let ok = raw.ok
        let data = raw.data

        if status == 429 {
            throw APIError.rateLimited(retryAfter: raw.retryAfter)
        }
        if status == 401 {
            if request.emitsAuthEvents, apiCode == "auth_required" || apiCode.isEmpty {
                await MainActor.run {
                    NotificationCenter.default.post(name: .qgramUnauthorized, object: nil)
                }
                throw APIError.unauthorized
            }
            throw APIError.api(code: apiCode.isEmpty ? "auth_required" : apiCode, message: apiMessage, status: status)
        }
        if status >= 400 || (ok == false && !apiCode.isEmpty) {
            let error = APIError.api(code: apiCode.isEmpty ? "bad_request" : apiCode,
                                     message: apiMessage,
                                     status: status)
            if error.isAccountRestriction {
                await MainActor.run {
                    NotificationCenter.default.post(name: .qgramAccountRestricted, object: error)
                }
            }
            throw error
        }
        return data
    }

    private func perform<T: Decodable>(_ request: Request, as type: T.Type) async throws -> T {
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private static func message(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: return "Нет подключения к интернету"
        case .timedOut: return "Сервер не отвечает. Попробуйте ещё раз."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Не удалось связаться с qgram.fun"
        case .networkConnectionLost: return "Соединение прервалось"
        case .secureConnectionFailed, .serverCertificateUntrusted:
            return "Проблема с защищённым соединением"
        default: return "Ошибка сети: \(error.localizedDescription)"
        }
    }

    // MARK: - Auth

    /// `/api/login` answers a 2FA-enabled account with HTTP 401 **and** a
    /// `challenge_token`, and every call sends a fresh e-mail code — so the
    /// request is made exactly once and the body is inspected directly.
    func login(username: String, password: String) async throws -> LoginOutcome {
        let raw = try await execute(Request(method: "POST", path: "api/login",
                                            body: .json(["username": username, "password": password]),
                                            emitsAuthEvents: false))
        if raw.status == 429 {
            throw APIError.rateLimited(retryAfter: raw.retryAfter)
        }
        if let challenge = raw.payload?["challenge_token"] as? String, !challenge.isEmpty {
            return .twoFactorRequired(TwoFactorChallenge(
                token: challenge,
                expiresIn: (raw.payload?["expires_in"] as? Int) ?? 600,
                message: (raw.payload?["message"] as? String) ?? "Код подтверждения отправлен на почту"
            ))
        }
        if raw.status >= 400 || raw.ok == false {
            throw APIError.api(code: raw.apiCode.isEmpty ? "invalid_credentials" : raw.apiCode,
                               message: raw.apiMessage,
                               status: raw.status)
        }
        do {
            let response = try JSONDecoder().decode(QLoginResponse.self, from: raw.data)
            guard !response.token.isEmpty else {
                throw APIError.api(code: "bad_request", message: "Сервер не выдал токен", status: raw.status)
            }
            token = response.token
            return .success(response)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func completeTwoFactor(challengeToken: String, code: String) async throws -> QLoginResponse {
        let request = Request(method: "POST", path: "api/login/2fa",
                              body: .json(["challenge_token": challengeToken, "code": code]),
                              emitsAuthEvents: false)
        let response = try await perform(request, as: QLoginResponse.self)
        token = response.token
        return response
    }

    func logout() async {
        _ = try? await perform(Request(method: "POST", path: "api/logout", emitsAuthEvents: false))
        token = nil
    }

    // MARK: - Me & profiles

    func me() async throws -> QUser {
        try await perform(Request(method: "GET", path: "api/me"), as: QUserEnvelope.self).user
    }

    func updateBio(_ bio: String) async throws -> QUser {
        try await perform(Request(method: "PATCH", path: "api/me/profile", body: .json(["bio": bio])),
                          as: QUserEnvelope.self).user
    }

    func uploadAvatar(imageData: Data, filename: String, mimeType: String) async throws -> QUser {
        var multipart = MultipartBody()
        multipart.appendFile(name: "avatar", filename: filename, mimeType: mimeType, data: imageData)
        return try await perform(Request(method: "POST", path: "api/me/avatar", body: .multipart(multipart)),
                                 as: QUserEnvelope.self).user
    }

    func uploadBanner(imageData: Data, filename: String, mimeType: String) async throws -> QUser {
        var multipart = MultipartBody()
        multipart.appendFile(name: "banner", filename: filename, mimeType: mimeType, data: imageData)
        return try await perform(Request(method: "POST", path: "api/me/banner", body: .multipart(multipart)),
                                 as: QUserEnvelope.self).user
    }

    func deleteBanner() async throws -> QUser {
        try await perform(Request(method: "DELETE", path: "api/me/banner"), as: QUserEnvelope.self).user
    }

    func profile(username: String, includePosts: Bool = true, limit: Int = 20) async throws -> QProfileEnvelope {
        try await perform(
            Request(method: "GET", path: "api/profiles/\(username.qgramPathEscaped)",
                    query: ["include_posts": includePosts ? "1" : "0", "limit": String(limit)]),
            as: QProfileEnvelope.self
        )
    }

    func user(username: String) async throws -> QUser {
        try await perform(Request(method: "GET", path: "api/users/\(username.qgramPathEscaped)"),
                          as: QUserEnvelope.self).user
    }

    func userPosts(username: String, limit: Int = 20, offset: Int = 0) async throws -> [QPost] {
        try await perform(
            Request(method: "GET", path: "api/users/\(username.qgramPathEscaped)/posts",
                    query: ["limit": String(limit), "offset": String(offset)]),
            as: QPostsEnvelope.self
        ).items
    }

    // MARK: - Posts

    func feed(limit: Int = 20, offset: Int = 0, username: String? = nil) async throws -> [QPost] {
        var query = ["limit": String(limit), "offset": String(offset)]
        if let username, !username.isEmpty { query["username"] = username }
        return try await perform(Request(method: "GET", path: "api/posts", query: query),
                                 as: QPostsEnvelope.self).items
    }

    func post(id: Int) async throws -> QPost {
        try await perform(Request(method: "GET", path: "api/posts/\(id)"), as: QPostEnvelope.self).post
    }

    // MARK: - Comments

    func comments(postID: Int, limit: Int = 30, offset: Int = 0,
                  order: String = "new", repliesPreview: Int = 3) async throws -> QCommentsEnvelope {
        try await perform(
            Request(method: "GET", path: "api/posts/\(postID)/comments",
                    query: [
                        "limit": String(limit),
                        "offset": String(offset),
                        "order": order,
                        "replies": String(repliesPreview),
                    ]),
            as: QCommentsEnvelope.self
        )
    }

    func replies(commentID: Int, limit: Int = 50, offset: Int = 0) async throws -> [QComment] {
        try await perform(
            Request(method: "GET", path: "api/comments/\(commentID)/replies",
                    query: ["limit": String(limit), "offset": String(offset)]),
            as: QCommentsEnvelope.self
        ).items
    }

    func createComment(postID: Int, body: String, parentID: Int?) async throws -> QCommentEnvelope {
        var payload: [String: Any] = ["body": body]
        if let parentID { payload["parent_id"] = parentID }
        return try await perform(Request(method: "POST", path: "api/posts/\(postID)/comments",
                                         body: .json(payload)),
                                 as: QCommentEnvelope.self)
    }

    @discardableResult
    func deleteComment(id: Int) async throws -> Int {
        try await perform(Request(method: "DELETE", path: "api/comments/\(id)"),
                          as: QCommentDeleteResponse.self).commentCount
    }

    // MARK: - Follows

    func follow(username: String) async throws -> QFollowResponse {
        try await perform(Request(method: "POST", path: "api/users/\(username.qgramPathEscaped)/follow"),
                          as: QFollowResponse.self)
    }

    func unfollow(username: String) async throws -> QFollowResponse {
        try await perform(Request(method: "DELETE", path: "api/users/\(username.qgramPathEscaped)/follow"),
                          as: QFollowResponse.self)
    }

    func followers(username: String, limit: Int = 30, offset: Int = 0) async throws -> QUsersEnvelope {
        try await perform(
            Request(method: "GET", path: "api/users/\(username.qgramPathEscaped)/followers",
                    query: ["limit": String(limit), "offset": String(offset)]),
            as: QUsersEnvelope.self
        )
    }

    func following(username: String, limit: Int = 30, offset: Int = 0) async throws -> QUsersEnvelope {
        try await perform(
            Request(method: "GET", path: "api/users/\(username.qgramPathEscaped)/following",
                    query: ["limit": String(limit), "offset": String(offset)]),
            as: QUsersEnvelope.self
        )
    }

    // MARK: - Notifications

    func notifications(limit: Int = 40, offset: Int = 0, unreadOnly: Bool = false) async throws -> QNotificationsEnvelope {
        try await perform(
            Request(method: "GET", path: "api/notifications",
                    query: [
                        "limit": String(limit),
                        "offset": String(offset),
                        "unread_only": unreadOnly ? "1" : "0",
                    ]),
            as: QNotificationsEnvelope.self
        )
    }

    @discardableResult
    func markNotificationsRead(ids: [Int] = []) async throws -> Int {
        var payload: [String: Any] = [:]
        if !ids.isEmpty { payload["ids"] = ids }
        return try await perform(Request(method: "POST", path: "api/notifications/read", body: .json(payload)),
                                 as: QUnreadCountResponse.self).unreadCount
    }

    // MARK: - Search

    func search(query: String, limit: Int = 20, scope: String = "all") async throws -> QSearchEnvelope {
        try await perform(
            Request(method: "GET", path: "api/search",
                    query: ["q": query, "limit": String(limit), "type": scope]),
            as: QSearchEnvelope.self
        )
    }

    // MARK: - Push devices

    @discardableResult
    func registerPushDevice(token: String, sandbox: Bool) async throws -> Bool {
        let payload: [String: Any] = [
            "token": token,
            "platform": "ios",
            "bundle_id": Bundle.main.bundleIdentifier ?? "fun.qgram.ios",
            "environment": sandbox ? "sandbox" : "production",
        ]
        try await perform(Request(method: "POST", path: "api/push/devices", body: .json(payload)))
        return true
    }

    func removePushDevice(token: String) async throws {
        try await perform(Request(method: "POST", path: "api/push/devices/remove",
                                  body: .json(["token": token])))
    }

    // MARK: - Registration

    func register(username: String, password: String, email: String) async throws -> QRegistrationChallenge {
        try await perform(
            Request(method: "POST", path: "api/register",
                    body: .json(["username": username, "password": password, "email": email]),
                    emitsAuthEvents: false),
            as: QRegistrationChallenge.self
        )
    }

    func resendRegistrationCode(regToken: String) async throws -> QRegistrationChallenge {
        try await perform(
            Request(method: "POST", path: "api/register/resend",
                    body: .json(["reg_token": regToken]),
                    emitsAuthEvents: false),
            as: QRegistrationChallenge.self
        )
    }

    func completeRegistration(regToken: String, code: String) async throws -> QLoginResponse {
        let response = try await perform(
            Request(method: "POST", path: "api/register/verify",
                    body: .json(["reg_token": regToken, "code": code]),
                    emitsAuthEvents: false),
            as: QLoginResponse.self
        )
        token = response.token
        return response
    }

    func createPost(content: String, isPrivate: Bool, images: [UploadImage]) async throws -> QPost {
        if images.isEmpty {
            return try await perform(
                Request(method: "POST", path: "api/posts",
                        body: .json(["content": content, "is_private": isPrivate])),
                as: QPostEnvelope.self
            ).post
        }
        var multipart = MultipartBody()
        multipart.appendField(name: "content", value: content)
        multipart.appendField(name: "is_private", value: isPrivate ? "1" : "0")
        for image in images {
            multipart.appendFile(name: "images", filename: image.filename, mimeType: image.mimeType, data: image.data)
        }
        return try await perform(Request(method: "POST", path: "api/posts", body: .multipart(multipart)),
                                 as: QPostEnvelope.self).post
    }

    func deletePost(id: Int) async throws {
        try await perform(Request(method: "DELETE", path: "api/posts/\(id)"))
    }

    func toggleLike(targetType: String, targetID: Int) async throws -> QLikeResponse {
        try await perform(Request(method: "POST", path: "api/like/\(targetType)/\(targetID)"),
                          as: QLikeResponse.self)
    }

    func toggleDislike(postID: Int) async throws -> QDislikeResponse {
        try await perform(Request(method: "POST", path: "api/dislike/post/\(postID)"),
                          as: QDislikeResponse.self)
    }

    // MARK: - Counters & presence

    func unreadChats() async throws -> Int {
        try await perform(Request(method: "GET", path: "api/unread-chats"), as: QCountResponse.self).count
    }

    func unreadNotifications() async throws -> Int {
        try await perform(Request(method: "GET", path: "api/unread-notifications"), as: QCountResponse.self).count
    }

    @discardableResult
    func setPresence(_ status: QPresence) async throws -> QPresenceResponse {
        try await perform(Request(method: "POST", path: "api/presence/me",
                                  body: .json(["status": status.rawValue])),
                          as: QPresenceResponse.self)
    }

    func presence(username: String) async throws -> QPresence {
        try await perform(Request(method: "GET", path: "api/users/\(username.qgramPathEscaped)/presence"),
                          as: QPresenceResponse.self).status
    }

    // MARK: - Chats

    func chats() async throws -> [QChatSummary] {
        try await perform(Request(method: "GET", path: "api/chats"), as: QChatsEnvelope.self).items
    }

    /// Newest page of a conversation.
    ///
    /// The endpoint only walks *backwards* when `before_id` is present; asking
    /// for `limit` alone returns the oldest messages instead of the latest, so
    /// the first page is fetched with a sentinel id.
    func latestMessages(convID: Int, limit: Int = 50, markRead: Bool = true) async throws -> QMessagesEnvelope {
        try await perform(
            Request(method: "GET", path: "api/chats/\(convID)/messages",
                    query: [
                        "limit": String(limit),
                        "before_id": String(AppConfig.latestMessagesSentinelID),
                        "mark_read": markRead ? "1" : "0",
                    ]),
            as: QMessagesEnvelope.self
        )
    }

    func olderMessages(convID: Int, beforeID: Int, limit: Int = 50) async throws -> QMessagesEnvelope {
        try await perform(
            Request(method: "GET", path: "api/chats/\(convID)/messages",
                    query: ["limit": String(limit), "before_id": String(beforeID), "mark_read": "0"]),
            as: QMessagesEnvelope.self
        )
    }

    func newMessages(convID: Int, afterID: Int, markRead: Bool = true) async throws -> QMessagesEnvelope {
        try await perform(
            Request(method: "GET", path: "api/chats/\(convID)/messages",
                    query: [
                        "limit": "100",
                        "after_id": String(afterID),
                        "mark_read": markRead ? "1" : "0",
                    ]),
            as: QMessagesEnvelope.self
        )
    }

    func startChat(username: String) async throws -> QStartChatResponse {
        try await perform(Request(method: "POST", path: "api/chats/start", body: .json(["username": username])),
                          as: QStartChatResponse.self)
    }

    func sendMessage(convID: Int, body: String, replyTo: Int?,
                     attachments: [QAttachment] = []) async throws -> QMessage {
        var payload: [String: Any] = ["body": body]
        if let replyTo { payload["reply_to_message_id"] = replyTo }
        if !attachments.isEmpty {
            payload["attachments"] = attachments.map(\.jsonObject)
        }
        return try await perform(Request(method: "POST", path: "api/chats/\(convID)/send", body: .json(payload)),
                                 as: QMessageEnvelope.self).message
    }

    /// Uploads an image for a chat message and returns the descriptor to pass
    /// back in `sendMessage(attachments:)`.
    func uploadChatAttachment(convID: Int, image: UploadImage) async throws -> QAttachment {
        var multipart = MultipartBody()
        multipart.appendFile(name: "file", filename: image.filename, mimeType: image.mimeType, data: image.data)
        return try await perform(Request(method: "POST", path: "api/chats/\(convID)/attachments",
                                         body: .multipart(multipart)),
                                 as: QAttachmentEnvelope.self).attachment
    }

    func editMessage(id: Int, body: String) async throws -> QMessage {
        try await perform(Request(method: "PATCH", path: "api/messages/\(id)", body: .json(["body": body])),
                          as: QMessageEnvelope.self).message
    }

    func deleteMessage(id: Int) async throws {
        try await perform(Request(method: "DELETE", path: "api/messages/\(id)"))
    }

    func react(messageID: Int, reaction: String) async throws -> QReactionEnvelope {
        try await perform(Request(method: "POST", path: "api/messages/\(messageID)/react",
                                  body: .json(["reaction": reaction])),
                          as: QReactionEnvelope.self)
    }

    func markRead(convID: Int, uptoMessageID: Int?) async throws {
        var payload: [String: Any] = [:]
        if let uptoMessageID { payload["upto_message_id"] = uptoMessageID }
        try await perform(Request(method: "POST", path: "api/chats/\(convID)/read", body: .json(payload)))
    }

    func setTyping(convID: Int, isTyping: Bool) async throws {
        try await perform(Request(method: "POST", path: "api/chats/\(convID)/typing",
                                  body: .json(["is_typing": isTyping])))
    }

    func typingUsers(convID: Int) async throws -> [QTypingUser] {
        try await perform(Request(method: "GET", path: "api/chats/\(convID)/typing"), as: QTypingEnvelope.self).items
    }
}

// MARK: - Upload helpers

struct UploadImage: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let filename: String
    let mimeType: String

    var sizeMB: Double { Double(data.count) / (1024 * 1024) }
}

struct MultipartBody {
    let boundary = "QGramBoundary-\(UUID().uuidString)"
    private(set) var data = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func appendField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func appendFile(name: String, filename: String, mimeType: String, data fileData: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")
    }

    /// Finishing boundary is appended lazily so callers cannot forget it.
    var finalized: Data {
        var copy = data
        copy.append("--\(boundary)--\r\n".data(using: .utf8) ?? Data())
        return copy
    }

    private mutating func append(_ string: String) {
        if let encoded = string.data(using: .utf8) {
            data.append(encoded)
        }
    }
}

extension String {
    /// Usernames are ASCII-ish but may contain characters that need escaping in
    /// a path segment.
    var qgramPathEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}
