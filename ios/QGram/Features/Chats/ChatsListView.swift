import SwiftUI

@MainActor
final class ChatsListViewModel: ObservableObject {
    @Published private(set) var chats: [QChatSummary] = []
    @Published private(set) var isLoading = false
    @Published var error: String?

    private let api = APIClient.shared

    var totalUnread: Int { chats.reduce(0) { $0 + $1.unreadCount } }

    func load(showSpinner: Bool = true) async {
        if showSpinner, chats.isEmpty { isLoading = true }
        do {
            let items = try await api.chats()
            // The API sorts by unread count; a messenger sorts by recency, with
            // pinned rooms on top.
            chats = items.sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned { return lhs.pinned }
                let left = lhs.lastActivityDate ?? .distantPast
                let right = rhs.lastActivityDate ?? .distantPast
                return left > right
            }
            error = nil
        } catch is CancellationError {
            // Ignored.
        } catch let error as APIError {
            if chats.isEmpty { self.error = error.userMessage }
        } catch {
            if chats.isEmpty { self.error = "Не удалось загрузить чаты" }
        }
        isLoading = false
    }
}

struct ChatsListView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.qNavigate) private var navigate
    @StateObject private var model = ChatsListViewModel()

    @State private var showNewChat = false
    @State private var isStartingChat = false

    var body: some View {
        Group {
            if model.isLoading && model.chats.isEmpty {
                VStack(spacing: QSpacing.md) {
                    ForEach(0..<6, id: \.self) { _ in QSkeletonRow(height: 68) }
                }
                .padding(QSpacing.md)
                .frame(maxHeight: .infinity, alignment: .top)
            } else if let error = model.error, model.chats.isEmpty {
                QErrorView(message: error) {
                    Task { await model.load() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.chats.isEmpty {
                QEmptyState(icon: "bubble.left.and.bubble.right",
                            title: "Пока нет диалогов",
                            subtitle: "Начните переписку — найдите человека по имени пользователя.",
                            actionTitle: "Новый чат") {
                    showNewChat = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: QSpacing.sm) {
                        ForEach(model.chats) { chat in
                            Button {
                                navigate(.chat(convID: chat.convID, title: chat.other.displayName))
                            } label: {
                                ChatRow(chat: chat)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, QSpacing.md)
                    .padding(.vertical, QSpacing.sm)
                }
            }
        }
        .background(QColor.bg.ignoresSafeArea())
        .navigationTitle("Чаты")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showNewChat = true
                } label: {
                    if isStartingChat {
                        ProgressView().controlSize(.small).tint(QColor.brand)
                    } else {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(QColor.text)
                    }
                }
                .disabled(isStartingChat)
            }
        }
        .refreshable { await model.load(showSpinner: false) }
        .sheet(isPresented: $showNewChat) {
            NavigationStack {
                SearchView { user in
                    start(with: user)
                }
            }
            .environmentObject(appState)
        }
        .task {
            await model.load()
            appState.setUnreadChats(model.totalUnread)
            // Keep the list warm while it is on screen.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: AppConfig.chatsListPollInterval * 1_000_000_000)
                if Task.isCancelled { return }
                await model.load(showSpinner: false)
                appState.setUnreadChats(model.totalUnread)
            }
        }
    }

    private func start(with user: QUser) {
        guard !isStartingChat else { return }
        isStartingChat = true
        Task {
            defer { isStartingChat = false }
            do {
                let response = try await APIClient.shared.startChat(username: user.username)
                navigate(.chat(convID: response.convID, title: user.displayName))
                await model.load(showSpinner: false)
            } catch {
                appState.showError(error)
            }
        }
    }
}

struct ChatRow: View {
    let chat: QChatSummary

    private var preview: String {
        if chat.typingCount > 0 { return "печатает…" }
        guard let last = chat.last else { return "Нет сообщений" }
        return last.body.isEmpty ? "Сообщение удалено" : last.body
    }

    var body: some View {
        HStack(spacing: QSpacing.md) {
            ZStack(alignment: .bottomTrailing) {
                QAvatar(url: chat.other.avatarURL, size: 50, ring: chat.other.isPremium)
                QPresenceDot(presence: chat.otherPresence, size: 13)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    QUserLabel(displayName: chat.other.displayName,
                               verified: chat.other.verified,
                               isPremium: chat.other.isPremium,
                               premiumEmoji: chat.other.premiumEmoji,
                               font: QFont.headline(15))
                    if chat.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundColor(QColor.muted)
                    }
                    if chat.muted {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 10))
                            .foregroundColor(QColor.muted)
                    }
                    Spacer(minLength: 0)
                    Text(QDate.relative(chat.lastActivityDate))
                        .font(QFont.caption(11))
                        .foregroundColor(QColor.muted)
                }
                HStack(spacing: 8) {
                    Text(preview)
                        .font(QFont.body(14))
                        .foregroundColor(chat.typingCount > 0 ? QColor.brandLight : QColor.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    QBadge(count: chat.unreadCount)
                }
            }
        }
        .padding(QSpacing.md)
        .background(QColor.card)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous)
                .strokeBorder(chat.unreadCount > 0 ? QColor.brand.opacity(0.35) : QColor.line, lineWidth: 1)
        )
    }
}
