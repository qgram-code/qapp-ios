import Foundation

// MARK: - Lenient decoding helpers
//
// The API is generous with its payloads (fields get added over time, some are
// null, some numeric fields arrive as strings). Decoding is therefore forgiving
// by design: a new or missing field must never break a screen.

extension KeyedDecodingContainer {
    func qString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return nil
    }

    func qInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }

    func qBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return ["1", "true", "yes", "on"].contains(value.lowercased())
        }
        return nil
    }

    func qStringArray(_ key: Key) -> [String] {
        (try? decodeIfPresent([String].self, forKey: key)) ?? []
    }
}

// MARK: - User

struct QUser: Codable, Identifiable, Equatable, Hashable {
    var id: Int
    var username: String
    var displayName: String
    var verified: Bool
    var isBanned: Bool
    var avatarPath: String
    var bannerPath: String
    var bio: String
    var isFrozen: Bool
    var isPremium: Bool
    var premiumEmoji: String
    var premiumColor: String
    var followersCount: Int?
    var followingCount: Int?
    var isFollowing: Bool?

    var handle: String { "@" + username }
    var avatarURL: URL? { AppConfig.baseURL.qgramResolved(avatarPath) }
    var bannerURL: URL? { AppConfig.baseURL.qgramResolved(bannerPath) }

    enum CodingKeys: String, CodingKey {
        case id, username, verified, bio
        case displayName = "display_name"
        case isBanned = "is_banned"
        case avatarPath = "avatar_path"
        case bannerPath = "banner_path"
        case isFrozen = "is_frozen"
        case isPremium = "is_premium"
        case premiumEmoji = "premium_emoji"
        case premiumColor = "premium_color"
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case isFollowing = "is_following"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.qInt(.id) ?? 0
        username = c.qString(.username) ?? ""
        displayName = c.qString(.displayName) ?? ("@" + (c.qString(.username) ?? ""))
        verified = c.qBool(.verified) ?? false
        isBanned = c.qBool(.isBanned) ?? false
        avatarPath = c.qString(.avatarPath) ?? ""
        bannerPath = c.qString(.bannerPath) ?? ""
        bio = c.qString(.bio) ?? ""
        isFrozen = c.qBool(.isFrozen) ?? false
        isPremium = c.qBool(.isPremium) ?? false
        premiumEmoji = c.qString(.premiumEmoji) ?? ""
        premiumColor = c.qString(.premiumColor) ?? ""
        followersCount = c.qInt(.followersCount)
        followingCount = c.qInt(.followingCount)
        isFollowing = c.qBool(.isFollowing)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(username, forKey: .username)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(verified, forKey: .verified)
        try c.encode(isBanned, forKey: .isBanned)
        try c.encode(avatarPath, forKey: .avatarPath)
        try c.encode(bannerPath, forKey: .bannerPath)
        try c.encode(bio, forKey: .bio)
        try c.encode(isFrozen, forKey: .isFrozen)
        try c.encode(isPremium, forKey: .isPremium)
        try c.encode(premiumEmoji, forKey: .premiumEmoji)
        try c.encode(premiumColor, forKey: .premiumColor)
        try c.encodeIfPresent(followersCount, forKey: .followersCount)
        try c.encodeIfPresent(followingCount, forKey: .followingCount)
        try c.encodeIfPresent(isFollowing, forKey: .isFollowing)
    }
}

// MARK: - Post

struct QPostAuthor: Codable, Equatable, Hashable {
    var id: Int
    var username: String
    var displayName: String
    var verified: Bool
    var avatarPath: String
    var isFrozen: Bool
    var isPremium: Bool
    var premiumEmoji: String

    var avatarURL: URL? { AppConfig.baseURL.qgramResolved(avatarPath) }

    enum CodingKeys: String, CodingKey {
        case id, username, verified
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case isFrozen = "is_frozen"
        case isPremium = "is_premium"
        case premiumEmoji = "premium_emoji"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.qInt(.id) ?? 0
        username = c.qString(.username) ?? ""
        displayName = c.qString(.displayName) ?? ("@" + (c.qString(.username) ?? ""))
        verified = c.qBool(.verified) ?? false
        avatarPath = c.qString(.avatarPath) ?? ""
        isFrozen = c.qBool(.isFrozen) ?? false
        isPremium = c.qBool(.isPremium) ?? false
        premiumEmoji = c.qString(.premiumEmoji) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(username, forKey: .username)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(verified, forKey: .verified)
        try c.encode(avatarPath, forKey: .avatarPath)
        try c.encode(isFrozen, forKey: .isFrozen)
        try c.encode(isPremium, forKey: .isPremium)
        try c.encode(premiumEmoji, forKey: .premiumEmoji)
    }
}

struct QPost: Codable, Identifiable, Equatable, Hashable {
    var id: Int
    var title: String
    var body: String
    var content: String
    var images: [String]
    var isPrivate: Bool
    var createdAt: String
    var createdFmt: String
    var liked: Bool
    var likeCount: Int
    var disliked: Bool
    var dislikeCount: Int
    var commentCount: Int
    var author: QPostAuthor

    var imageURLs: [URL] { images.compactMap { AppConfig.baseURL.qgramResolved($0) } }
    var createdDate: Date? { QDate.parse(createdAt) }

    enum CodingKeys: String, CodingKey {
        case id, title, body, content, images, liked, disliked, author
        case isPrivate = "is_private"
        case createdAt = "created_at"
        case createdFmt = "created_fmt"
        case likeCount = "like_count"
        case dislikeCount = "dislike_count"
        case commentCount = "comment_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.qInt(.id) ?? 0
        title = c.qString(.title) ?? ""
        body = c.qString(.body) ?? ""
        let joined = [title, body].filter { !$0.isEmpty }.joined(separator: "\n")
        content = (c.qString(.content) ?? joined).trimmingCharacters(in: .whitespacesAndNewlines)
        images = c.qStringArray(.images)
        isPrivate = c.qBool(.isPrivate) ?? false
        createdAt = c.qString(.createdAt) ?? ""
        createdFmt = c.qString(.createdFmt) ?? ""
        liked = c.qBool(.liked) ?? false
        likeCount = c.qInt(.likeCount) ?? 0
        disliked = c.qBool(.disliked) ?? false
        dislikeCount = c.qInt(.dislikeCount) ?? 0
        commentCount = c.qInt(.commentCount) ?? 0
        author = (try? c.decode(QPostAuthor.self, forKey: .author)) ?? QPostAuthor.placeholder
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encode(content, forKey: .content)
        try c.encode(images, forKey: .images)
        try c.encode(isPrivate, forKey: .isPrivate)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(createdFmt, forKey: .createdFmt)
        try c.encode(liked, forKey: .liked)
        try c.encode(likeCount, forKey: .likeCount)
        try c.encode(disliked, forKey: .disliked)
        try c.encode(dislikeCount, forKey: .dislikeCount)
        try c.encode(commentCount, forKey: .commentCount)
        try c.encode(author, forKey: .author)
    }
}

extension QPostAuthor {
    static let placeholder = QPostAuthor(id: 0, username: "unknown", displayName: "@unknown",
                                         verified: false, avatarPath: "", isFrozen: false,
                                         isPremium: false, premiumEmoji: "")

    init(id: Int, username: String, displayName: String, verified: Bool, avatarPath: String,
         isFrozen: Bool, isPremium: Bool, premiumEmoji: String) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.verified = verified
        self.avatarPath = avatarPath
        self.isFrozen = isFrozen
        self.isPremium = isPremium
        self.premiumEmoji = premiumEmoji
    }
}

// MARK: - Comment

struct QComment: Decodable, Identifiable, Equatable, Hashable {
    var id: Int
    var postID: Int
    var parentID: Int?
    var body: String
    var createdAt: String
    var createdFmt: String
    var likeCount: Int
    var liked: Bool
    var replyCount: Int
    var canDelete: Bool
    var author: QPostAuthor
    var replies: [QComment]

    var createdDate: Date? { QDate.parse(createdAt) }
    var isReply: Bool { parentID != nil }

    enum CodingKeys: String, CodingKey {
        case id, body, liked, author, replies
        case postID = "post_id"
        case parentID = "parent_id"
        case createdAt = "created_at"
        case createdFmt = "created_fmt"
        case likeCount = "like_count"
        case replyCount = "reply_count"
        case canDelete = "can_delete"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.qInt(.id) ?? 0
        postID = c.qInt(.postID) ?? 0
        parentID = c.qInt(.parentID)
        body = c.qString(.body) ?? ""
        createdAt = c.qString(.createdAt) ?? ""
        createdFmt = c.qString(.createdFmt) ?? ""
        likeCount = c.qInt(.likeCount) ?? 0
        liked = c.qBool(.liked) ?? false
        replyCount = c.qInt(.replyCount) ?? 0
        canDelete = c.qBool(.canDelete) ?? false
        author = (try? c.decode(QPostAuthor.self, forKey: .author)) ?? QPostAuthor.placeholder
        replies = (try? c.decodeIfPresent([QComment].self, forKey: .replies)) ?? []
    }
}

// MARK: - Notifications

enum QNotificationKind: String, Codable {
    case likePost = "like_post"
    case likeComment = "like_comment"
    case commentPost = "comment_post"
    case replyComment = "reply_comment"
    case follow
    case unknown

    init(apiValue: String?) {
        self = QNotificationKind(rawValue: (apiValue ?? "").lowercased()) ?? .unknown
    }

    var icon: String {
        switch self {
        case .likePost, .likeComment: return "heart.fill"
        case .commentPost: return "bubble.right.fill"
        case .replyComment: return "arrowshape.turn.up.left.fill"
        case .follow: return "person.badge.plus.fill"
        case .unknown: return "bell.fill"
        }
    }
}

struct QNotification: Decodable, Identifiable, Equatable, Hashable {
    var id: Int
    var kind: QNotificationKind
    var actionText: String
    var isRead: Bool
    var createdAt: String
    var createdFmt: String
    var postID: Int?
    var commentID: Int?
    var actor: QPostAuthor

    var createdDate: Date? { QDate.parse(createdAt) }

    enum CodingKeys: String, CodingKey {
        case id, type, actor
        case actionText = "action_text"
        case isRead = "is_read"
        case createdAt = "created_at"
        case createdFmt = "created_fmt"
        case postID = "post_id"
        case commentID = "comment_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.qInt(.id) ?? 0
        kind = QNotificationKind(apiValue: c.qString(.type))
        actionText = c.qString(.actionText) ?? ""
        isRead = c.qBool(.isRead) ?? false
        createdAt = c.qString(.createdAt) ?? ""
        createdFmt = c.qString(.createdFmt) ?? ""
        postID = c.qInt(.postID)
        commentID = c.qInt(.commentID)
        actor = (try? c.decode(QPostAuthor.self, forKey: .actor)) ?? QPostAuthor.placeholder
    }
}

// MARK: - Attachments

struct QAttachment: Codable, Equatable, Hashable, Identifiable {
    var type: String
    var path: String
    var url: String
    var name: String
    var size: Int
    var mime: String

    var id: String { url.isEmpty ? path : url }
    var isImage: Bool { type.lowercased() == "image" }

    /// Attachments are stored as free-form JSON, so a message could carry a
    /// link to any host. Only images served from our own origin are rendered.
    var trustedImageURL: URL? {
        guard isImage else { return nil }
        guard let resolved = AppConfig.baseURL.qgramResolved(path.isEmpty ? url : path) else { return nil }
        guard resolved.host == AppConfig.baseURL.host else { return nil }
        return resolved
    }

    enum CodingKeys: String, CodingKey {
        case type, path, url, name, size, mime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = c.qString(.type) ?? ""
        path = c.qString(.path) ?? ""
        url = c.qString(.url) ?? ""
        name = c.qString(.name) ?? ""
        size = c.qInt(.size) ?? 0
        mime = c.qString(.mime) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(path, forKey: .path)
        try c.encode(url, forKey: .url)
        try c.encode(name, forKey: .name)
        try c.encode(size, forKey: .size)
        try c.encode(mime, forKey: .mime)
    }

    /// Dictionary form for the `attachments` array of the send endpoint.
    var jsonObject: [String: Any] {
        ["type": type, "path": path, "url": url, "name": name, "size": size, "mime": mime]
    }
}

// MARK: - Chat

enum QPresence: String, Codable, CaseIterable {
    case online
    case away
    case sleep
    case doNotDisturb = "do_not_disturb"
    case offline

    init(apiValue: String?) {
        self = QPresence(rawValue: (apiValue ?? "").lowercased()) ?? .offline
    }

    var title: String {
        switch self {
        case .online: return "в сети"
        case .away: return "отошёл"
        case .sleep: return "спит"
        case .doNotDisturb: return "не беспокоить"
        case .offline: return "не в сети"
        }
    }

    var isOnline: Bool { self == .online || self == .away || self == .doNotDisturb }
}

struct QChatUser: Codable, Equatable, Hashable {
    var id: Int
    var username: String
    var displayName: String
    var verified: Bool
    var avatarPath: String
    var isFrozen: Bool
    var isDeleted: Bool
    var isPremium: Bool
    var premiumEmoji: String

    var avatarURL: URL? { AppConfig.baseURL.qgramResolved(avatarPath) }

    enum CodingKeys: String, CodingKey {
        case id, username, verified
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case isFrozen = "is_frozen"
        case isDeleted = "is_deleted"
        case isPremium = "is_premium"
        case premiumEmoji = "premium_emoji"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.qInt(.id) ?? 0
        username = c.qString(.username) ?? ""
        displayName = c.qString(.displayName) ?? ("@" + (c.qString(.username) ?? ""))
        verified = c.qBool(.verified) ?? false
        avatarPath = c.qString(.avatarPath) ?? ""
        isFrozen = c.qBool(.isFrozen) ?? false
        isDeleted = c.qBool(.isDeleted) ?? false
        isPremium = c.qBool(.isPremium) ?? false
        premiumEmoji = c.qString(.premiumEmoji) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(username, forKey: .username)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(verified, forKey: .verified)
        try c.encode(avatarPath, forKey: .avatarPath)
        try c.encode(isFrozen, forKey: .isFrozen)
        try c.encode(isDeleted, forKey: .isDeleted)
        try c.encode(isPremium, forKey: .isPremium)
        try c.encode(premiumEmoji, forKey: .premiumEmoji)
    }
}

struct QChatLastMessage: Codable, Equatable, Hashable {
    var id: Int
    var body: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, body
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.qInt(.id) ?? 0
        body = c.qString(.body) ?? ""
        createdAt = c.qString(.createdAt) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(body, forKey: .body)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

struct QChatSummary: Codable, Identifiable, Equatable, Hashable {
    var convID: Int
    var other: QChatUser
    var last: QChatLastMessage?
    var unreadCount: Int
    var typingCount: Int
    var otherPresence: QPresence
    var muted: Bool
    var pinned: Bool
    var lastMessageAt: String

    var id: Int { convID }
    var lastActivityDate: Date? { QDate.parse(lastMessageAt.isEmpty ? (last?.createdAt ?? "") : lastMessageAt) }

    enum CodingKeys: String, CodingKey {
        case other, last, muted, pinned
        case convID = "conv_id"
        case unreadCount = "unread_count"
        case typingCount = "typing_count"
        case otherPresence = "other_presence"
        case lastMessageAt = "last_message_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        convID = c.qInt(.convID) ?? 0
        other = try c.decode(QChatUser.self, forKey: .other)
        last = try? c.decodeIfPresent(QChatLastMessage.self, forKey: .last)
        unreadCount = c.qInt(.unreadCount) ?? 0
        typingCount = c.qInt(.typingCount) ?? 0
        otherPresence = QPresence(apiValue: c.qString(.otherPresence))
        muted = c.qBool(.muted) ?? false
        pinned = c.qBool(.pinned) ?? false
        lastMessageAt = c.qString(.lastMessageAt) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(convID, forKey: .convID)
        try c.encode(other, forKey: .other)
        try c.encodeIfPresent(last, forKey: .last)
        try c.encode(unreadCount, forKey: .unreadCount)
        try c.encode(typingCount, forKey: .typingCount)
        try c.encode(otherPresence.rawValue, forKey: .otherPresence)
        try c.encode(muted, forKey: .muted)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(lastMessageAt, forKey: .lastMessageAt)
    }
}

struct QReaction: Codable, Equatable, Hashable, Identifiable {
    var reaction: String
    var count: Int
    var me: Bool

    var id: String { reaction }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reaction = c.qString(.reaction) ?? ""
        count = c.qInt(.count) ?? 0
        me = c.qBool(.me) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case reaction, count, me
    }
}

struct QReplyPreview: Codable, Equatable, Hashable {
    var id: Int
    var senderID: Int
    var username: String
    var body: String
    var isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, username, body
        case senderID = "sender_id"
        case isDeleted = "is_deleted"
    }

    init(id: Int, senderID: Int, username: String, body: String, isDeleted: Bool) {
        self.id = id
        self.senderID = senderID
        self.username = username
        self.body = body
        self.isDeleted = isDeleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.qInt(.id) ?? 0
        senderID = c.qInt(.senderID) ?? 0
        username = c.qString(.username) ?? ""
        body = c.qString(.body) ?? ""
        isDeleted = c.qBool(.isDeleted) ?? false
    }
}

struct QMessage: Codable, Identifiable, Equatable, Hashable {
    var id: Int
    var senderID: Int
    var body: String
    var createdAt: String
    var createdFmt: String
    var readAt: String
    var editedAt: String
    var isDeleted: Bool
    var replyToMessageID: Int?
    var username: String
    var displayName: String
    var avatarPath: String
    var verified: Bool
    var isPremium: Bool
    var premiumEmoji: String
    var reactions: [QReaction]
    var replyPreview: QReplyPreview?
    var attachments: [QAttachment]

    /// Set for optimistic bubbles that have not been confirmed by the server.
    var isPending: Bool = false
    var failed: Bool = false

    var createdDate: Date? { QDate.parse(createdAt) }
    var isEdited: Bool { !editedAt.isEmpty }
    var isRead: Bool { !readAt.isEmpty }
    var avatarURL: URL? { AppConfig.baseURL.qgramResolved(avatarPath) }

    enum CodingKeys: String, CodingKey {
        case id, body, username, verified, reactions
        case senderID = "sender_id"
        case createdAt = "created_at"
        case createdFmt = "created_fmt"
        case readAt = "read_at"
        case editedAt = "edited_at"
        case isDeleted = "is_deleted"
        case replyToMessageID = "reply_to_message_id"
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case isPremium = "is_premium"
        case premiumEmoji = "premium_emoji"
        case replyPreview = "reply_preview"
        case attachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.qInt(.id) ?? 0
        senderID = c.qInt(.senderID) ?? 0
        body = c.qString(.body) ?? ""
        createdAt = c.qString(.createdAt) ?? ""
        createdFmt = c.qString(.createdFmt) ?? ""
        readAt = c.qString(.readAt) ?? ""
        editedAt = c.qString(.editedAt) ?? ""
        isDeleted = c.qBool(.isDeleted) ?? false
        replyToMessageID = c.qInt(.replyToMessageID)
        username = c.qString(.username) ?? ""
        displayName = c.qString(.displayName) ?? ("@" + (c.qString(.username) ?? ""))
        avatarPath = c.qString(.avatarPath) ?? ""
        verified = c.qBool(.verified) ?? false
        isPremium = c.qBool(.isPremium) ?? false
        premiumEmoji = c.qString(.premiumEmoji) ?? ""
        reactions = (try? c.decodeIfPresent([QReaction].self, forKey: .reactions)) ?? []
        replyPreview = try? c.decodeIfPresent(QReplyPreview.self, forKey: .replyPreview)
        attachments = (try? c.decodeIfPresent([QAttachment].self, forKey: .attachments)) ?? []
        isPending = false
        failed = false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(senderID, forKey: .senderID)
        try c.encode(body, forKey: .body)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(createdFmt, forKey: .createdFmt)
        try c.encode(readAt, forKey: .readAt)
        try c.encode(editedAt, forKey: .editedAt)
        try c.encode(isDeleted, forKey: .isDeleted)
        try c.encodeIfPresent(replyToMessageID, forKey: .replyToMessageID)
        try c.encode(username, forKey: .username)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(avatarPath, forKey: .avatarPath)
        try c.encode(verified, forKey: .verified)
        try c.encode(isPremium, forKey: .isPremium)
        try c.encode(premiumEmoji, forKey: .premiumEmoji)
        try c.encode(reactions, forKey: .reactions)
        try c.encodeIfPresent(replyPreview, forKey: .replyPreview)
        try c.encode(attachments, forKey: .attachments)
    }

    /// Local placeholder used while a send request is in flight.
    static func pending(localID: Int, body: String, senderID: Int,
                        replyTo: QReplyPreview?, attachments: [QAttachment] = []) -> QMessage {
        var message = QMessage(empty: ())
        message.id = localID
        message.senderID = senderID
        message.body = body
        message.createdAt = QDate.nowUTCString()
        message.isPending = true
        message.replyToMessageID = replyTo?.id
        message.replyPreview = replyTo
        message.attachments = attachments
        return message
    }

    private init(empty: ()) {
        id = 0
        senderID = 0
        body = ""
        createdAt = ""
        createdFmt = ""
        readAt = ""
        editedAt = ""
        isDeleted = false
        replyToMessageID = nil
        username = ""
        displayName = ""
        avatarPath = ""
        verified = false
        isPremium = false
        premiumEmoji = ""
        reactions = []
        replyPreview = nil
        attachments = []
        isPending = false
        failed = false
    }
}

struct QTypingUser: Codable, Identifiable, Equatable {
    var userID: Int
    var username: String

    var id: Int { userID }

    enum CodingKeys: String, CodingKey {
        case username
        case userID = "user_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = c.qInt(.userID) ?? 0
        username = c.qString(.username) ?? ""
    }
}

// MARK: - Envelopes

struct QLoginResponse: Decodable {
    var token: String
    var user: QUser

    enum CodingKeys: String, CodingKey { case token, user }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = c.qString(.token) ?? ""
        user = try c.decode(QUser.self, forKey: .user)
    }
}

struct QUserEnvelope: Decodable {
    var user: QUser
}

struct QProfileEnvelope: Decodable {
    var profile: QUser
    var posts: [QPost]

    enum CodingKeys: String, CodingKey { case profile, posts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try c.decode(QUser.self, forKey: .profile)
        posts = (try? c.decodeIfPresent([QPost].self, forKey: .posts)) ?? []
    }
}

struct QPostsEnvelope: Decodable {
    var items: [QPost]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([QPost].self, forKey: .items)) ?? []
    }
}

struct QPostEnvelope: Decodable {
    var post: QPost
}

struct QCommentsEnvelope: Decodable {
    var items: [QComment]
    var total: Int
    var canComment: Bool

    enum CodingKeys: String, CodingKey {
        case items, total
        case canComment = "can_comment"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([QComment].self, forKey: .items)) ?? []
        total = c.qInt(.total) ?? 0
        canComment = c.qBool(.canComment) ?? false
    }
}

struct QCommentEnvelope: Decodable {
    var comment: QComment
    var commentCount: Int

    enum CodingKeys: String, CodingKey {
        case comment
        case commentCount = "comment_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        comment = try c.decode(QComment.self, forKey: .comment)
        commentCount = c.qInt(.commentCount) ?? 0
    }
}

struct QCommentDeleteResponse: Decodable {
    var commentCount: Int

    enum CodingKeys: String, CodingKey { case commentCount = "comment_count" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        commentCount = c.qInt(.commentCount) ?? 0
    }
}

struct QFollowResponse: Decodable {
    var followersCount: Int
    var followingCount: Int
    var isFollowing: Bool

    enum CodingKeys: String, CodingKey {
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case isFollowing = "is_following"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        followersCount = c.qInt(.followersCount) ?? 0
        followingCount = c.qInt(.followingCount) ?? 0
        isFollowing = c.qBool(.isFollowing) ?? false
    }
}

struct QUsersEnvelope: Decodable {
    var items: [QUser]
    var total: Int

    enum CodingKeys: String, CodingKey { case items, total }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([QUser].self, forKey: .items)) ?? []
        total = c.qInt(.total) ?? 0
    }
}

struct QNotificationsEnvelope: Decodable {
    var items: [QNotification]
    var unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case items
        case unreadCount = "unread_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([QNotification].self, forKey: .items)) ?? []
        unreadCount = c.qInt(.unreadCount) ?? 0
    }
}

struct QUnreadCountResponse: Decodable {
    var unreadCount: Int

    enum CodingKeys: String, CodingKey { case unreadCount = "unread_count" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unreadCount = c.qInt(.unreadCount) ?? 0
    }
}

struct QSearchEnvelope: Decodable {
    var users: [QUser]
    var posts: [QPost]

    enum CodingKeys: String, CodingKey { case users, posts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        users = (try? c.decodeIfPresent([QUser].self, forKey: .users)) ?? []
        posts = (try? c.decodeIfPresent([QPost].self, forKey: .posts)) ?? []
    }
}

struct QAttachmentEnvelope: Decodable {
    var attachment: QAttachment
}

struct QRegistrationChallenge: Decodable, Equatable {
    var regToken: String
    var expiresIn: Int
    var message: String

    enum CodingKeys: String, CodingKey {
        case message
        case regToken = "reg_token"
        case expiresIn = "expires_in"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        regToken = c.qString(.regToken) ?? ""
        expiresIn = c.qInt(.expiresIn) ?? 600
        message = c.qString(.message) ?? "Код подтверждения отправлен на почту"
    }
}

struct QLikeResponse: Decodable {
    var liked: Bool
    var likeCount: Int
    var disliked: Bool?
    var dislikeCount: Int?

    enum CodingKeys: String, CodingKey {
        case liked, disliked
        case likeCount = "like_count"
        case dislikeCount = "dislike_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        liked = c.qBool(.liked) ?? false
        likeCount = c.qInt(.likeCount) ?? 0
        disliked = c.qBool(.disliked)
        dislikeCount = c.qInt(.dislikeCount)
    }
}

struct QDislikeResponse: Decodable {
    var liked: Bool
    var likeCount: Int
    var disliked: Bool
    var dislikeCount: Int

    enum CodingKeys: String, CodingKey {
        case liked, disliked
        case likeCount = "like_count"
        case dislikeCount = "dislike_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        liked = c.qBool(.liked) ?? false
        likeCount = c.qInt(.likeCount) ?? 0
        disliked = c.qBool(.disliked) ?? false
        dislikeCount = c.qInt(.dislikeCount) ?? 0
    }
}

struct QChatsEnvelope: Decodable {
    var items: [QChatSummary]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([QChatSummary].self, forKey: .items)) ?? []
    }
}

struct QMessagesEnvelope: Decodable {
    var convID: Int
    var other: QChatUser?
    var messages: [QMessage]
    var hasMoreBefore: Bool

    enum CodingKeys: String, CodingKey {
        case other, messages, items, paging
        case convID = "conv_id"
    }

    enum PagingKeys: String, CodingKey {
        case hasMoreBefore = "has_more_before"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        convID = c.qInt(.convID) ?? 0
        other = try? c.decodeIfPresent(QChatUser.self, forKey: .other)
        let items = (try? c.decodeIfPresent([QMessage].self, forKey: .items)) ?? []
        let plain = (try? c.decodeIfPresent([QMessage].self, forKey: .messages)) ?? []
        messages = items.isEmpty ? plain : items
        if let paging = try? c.nestedContainer(keyedBy: PagingKeys.self, forKey: .paging) {
            hasMoreBefore = paging.qBool(.hasMoreBefore) ?? false
        } else {
            hasMoreBefore = false
        }
    }
}

struct QMessageEnvelope: Decodable {
    var message: QMessage
    var convID: Int?

    enum CodingKeys: String, CodingKey {
        case message
        case convID = "conv_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = try c.decode(QMessage.self, forKey: .message)
        convID = c.qInt(.convID)
    }
}

struct QReactionEnvelope: Decodable {
    var messageID: Int
    var reactions: [QReaction]

    enum CodingKeys: String, CodingKey {
        case reactions
        case messageID = "message_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messageID = c.qInt(.messageID) ?? 0
        reactions = (try? c.decodeIfPresent([QReaction].self, forKey: .reactions)) ?? []
    }
}

struct QTypingEnvelope: Decodable {
    var items: [QTypingUser]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([QTypingUser].self, forKey: .items)) ?? []
    }
}

struct QStartChatResponse: Decodable {
    var convID: Int
    var otherID: Int

    enum CodingKeys: String, CodingKey {
        case convID = "conv_id"
        case otherID = "other_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        convID = c.qInt(.convID) ?? 0
        otherID = c.qInt(.otherID) ?? 0
    }
}

struct QCountResponse: Decodable {
    var count: Int

    enum CodingKeys: String, CodingKey { case count }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = c.qInt(.count) ?? 0
    }
}

struct QPresenceResponse: Decodable {
    var status: QPresence
    var lastSeenAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case lastSeenAt = "last_seen_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = QPresence(apiValue: c.qString(.status))
        lastSeenAt = c.qString(.lastSeenAt) ?? ""
    }
}

// MARK: - URL helpers

extension URL {
    /// Resolves an API path (`/static/uploads/…`) or an absolute URL against the
    /// configured host. Empty values yield `nil` so views can fall back to a
    /// placeholder instead of firing a doomed request.
    func qgramResolved(_ pathOrURL: String?) -> URL? {
        guard let raw = pathOrURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? raw
        return URL(string: encoded, relativeTo: self)?.absoluteURL
    }
}
