import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [QMessage] = []
    @Published private(set) var other: QChatUser?
    @Published private(set) var presence: QPresence = .offline
    @Published private(set) var isLoading = true
    @Published private(set) var isLoadingOlder = false
    @Published private(set) var hasMoreBefore = false
    @Published private(set) var isTypingRemote = false
    @Published private(set) var isSending = false
    @Published var error: String?
    @Published var draft: String = ""
    @Published var replyTo: QMessage?
    @Published var editing: QMessage?
    @Published private(set) var pendingAttachments: [QAttachment] = []
    @Published private(set) var isUploading = false

    let convID: Int
    private let api = APIClient.shared
    private var pollTask: Task<Void, Never>?
    private var lastTypingPing: Date?
    private var nextLocalID = -1
    private var cycle = 0

    init(convID: Int) {
        self.convID = convID
    }

    var canSend: Bool {
        guard !isSending, !isUploading else { return false }
        // An image with no caption is a valid message.
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
    }

    /// Highest id confirmed by the server (optimistic rows use negative ids).
    private var lastServerID: Int {
        messages.filter { $0.id > 0 }.map(\.id).max() ?? 0
    }

    // MARK: - Lifecycle

    func start() async {
        await loadLatest()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: AppConfig.chatPollInterval * 1_000_000_000)
                if Task.isCancelled { return }
                await self?.poll()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        let id = convID
        Task { try? await APIClient.shared.setTyping(convID: id, isTyping: false) }
    }

    // MARK: - Loading

    func loadLatest() async {
        do {
            let envelope = try await api.latestMessages(convID: convID, limit: 50, markRead: true)
            other = envelope.other ?? other
            hasMoreBefore = envelope.hasMoreBefore
            merge(envelope.messages)
            error = nil
            isLoading = false
            if let username = other?.username {
                presence = (try? await api.presence(username: username)) ?? .offline
            }
        } catch is CancellationError {
            // Ignored.
        } catch let error as APIError {
            isLoading = false
            if messages.isEmpty { self.error = error.userMessage }
        } catch {
            isLoading = false
            if messages.isEmpty { self.error = "Не удалось загрузить переписку" }
        }
    }

    func loadOlder() async {
        guard hasMoreBefore, !isLoadingOlder else { return }
        guard let oldest = messages.filter({ $0.id > 0 }).map(\.id).min() else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let envelope = try await api.olderMessages(convID: convID, beforeID: oldest, limit: 50)
            hasMoreBefore = envelope.hasMoreBefore
            merge(envelope.messages)
        } catch {
            hasMoreBefore = false
        }
    }

    private func poll() async {
        cycle += 1
        let after = lastServerID
        do {
            let envelope = try await api.newMessages(convID: convID, afterID: after, markRead: true)
            merge(envelope.messages)
            // The typing endpoint already excludes the current user.
            if let typing = try? await api.typingUsers(convID: convID) {
                isTypingRemote = !typing.isEmpty
            }
            // Read receipts, edits and deletions of already-loaded messages only
            // appear in a full page refresh, so do one every few cycles.
            if cycle % 5 == 0 {
                if let refreshed = try? await api.latestMessages(convID: convID, limit: 50, markRead: false) {
                    merge(refreshed.messages)
                    if let username = other?.username {
                        presence = (try? await api.presence(username: username)) ?? presence
                    }
                }
            }
        } catch is CancellationError {
            // Ignored.
        } catch {
            // Polling stays silent: a transient failure must not blow up the UI.
        }
    }

    /// Merges a server page into the local list: server rows win, optimistic
    /// rows stay at the end until their real counterpart arrives.
    private func merge(_ incoming: [QMessage]) {
        guard !incoming.isEmpty else { return }
        var byID: [Int: QMessage] = [:]
        for message in messages where message.id > 0 {
            byID[message.id] = message
        }
        for message in incoming {
            byID[message.id] = message
        }
        let incomingBodies = Set(incoming.map(\.body).filter { !$0.isEmpty })
        var pending = messages.filter { $0.id < 0 }
        pending.removeAll { $0.isPending && !$0.body.isEmpty && incomingBodies.contains($0.body) }

        // Local ids count down from -1, so descending id is chronological order.
        messages = byID.values.sorted { $0.id < $1.id } + pending.sorted { $0.id > $1.id }
    }

    // MARK: - Sending

    /// Uploads an image and keeps it attached to the draft until it is sent.
    func attach(_ image: UploadImage) async {
        guard pendingAttachments.count < 10 else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            let attachment = try await api.uploadChatAttachment(convID: convID, image: image)
            pendingAttachments.append(attachment)
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось загрузить изображение"
        }
    }

    func removeAttachment(_ attachment: QAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    func send(myID: Int) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        if let editing {
            guard !text.isEmpty else { return }
            await saveEdit(message: editing, newBody: text)
            return
        }

        isSending = true
        defer { isSending = false }

        let localID = nextLocalID
        nextLocalID -= 1
        let attachments = pendingAttachments
        let placeholder = QMessage.pending(localID: localID, body: text, senderID: myID,
                                           replyTo: replyTo.map(previewFor),
                                           attachments: attachments)
        messages.append(placeholder)
        let replyID = replyTo?.id
        draft = ""
        replyTo = nil
        pendingAttachments = []

        do {
            let sent = try await api.sendMessage(convID: convID, body: text,
                                                 replyTo: replyID, attachments: attachments)
            messages.removeAll { $0.id == localID }
            merge([sent])
            try? await api.setTyping(convID: convID, isTyping: false)
        } catch {
            if let index = messages.firstIndex(where: { $0.id == localID }) {
                messages[index].isPending = false
                messages[index].failed = true
            }
            if let apiError = error as? APIError {
                self.error = apiError.userMessage
            }
        }
    }

    func retry(_ message: QMessage, myID: Int) async {
        guard message.failed else { return }
        messages.removeAll { $0.id == message.id }
        draft = message.body
        pendingAttachments = message.attachments
        await send(myID: myID)
    }

    func discard(_ message: QMessage) {
        messages.removeAll { $0.id == message.id }
    }

    private func saveEdit(message: QMessage, newBody: String) async {
        isSending = true
        defer { isSending = false }
        do {
            let updated = try await api.editMessage(id: message.id, body: newBody)
            merge([updated])
            draft = ""
            editing = nil
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось изменить сообщение"
        }
    }

    func beginEdit(_ message: QMessage) {
        editing = message
        replyTo = nil
        draft = message.body
    }

    func cancelEdit() {
        editing = nil
        draft = ""
    }

    func delete(_ message: QMessage) async {
        guard message.id > 0 else {
            discard(message)
            return
        }
        do {
            try await api.deleteMessage(id: message.id)
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index].isDeleted = true
                messages[index].body = ""
            }
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось удалить сообщение"
        }
    }

    func react(_ message: QMessage, reaction: String) async {
        guard message.id > 0 else { return }
        do {
            let response = try await api.react(messageID: message.id, reaction: reaction)
            if let index = messages.firstIndex(where: { $0.id == response.messageID }) {
                messages[index].reactions = response.reactions
            }
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось поставить реакцию"
        }
    }

    // MARK: - Typing

    func draftChanged() {
        guard !draft.isEmpty, editing == nil else { return }
        let now = Date()
        if let last = lastTypingPing, now.timeIntervalSince(last) < AppConfig.typingPingInterval { return }
        lastTypingPing = now
        let id = convID
        Task { try? await APIClient.shared.setTyping(convID: id, isTyping: true) }
    }

    private func previewFor(_ message: QMessage) -> QReplyPreview {
        QReplyPreview(id: message.id,
                      senderID: message.senderID,
                      username: message.username,
                      body: String(message.body.prefix(120)),
                      isDeleted: message.isDeleted)
    }
}
