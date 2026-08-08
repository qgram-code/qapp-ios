import SwiftUI

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published private(set) var items: [QNotification] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var isLoading = true
    @Published private(set) var isLoadingMore = false
    @Published var unreadOnly = false
    @Published var error: String?

    private let api = APIClient.shared
    private let pageSize = 40
    private var hasMore = true

    func load() async {
        do {
            let envelope = try await api.notifications(limit: pageSize, offset: 0, unreadOnly: unreadOnly)
            items = envelope.items
            unreadCount = envelope.unreadCount
            hasMore = envelope.items.count == pageSize
            error = nil
        } catch is CancellationError {
            // Ignored.
        } catch let error as APIError {
            if items.isEmpty { self.error = error.userMessage }
        } catch {
            if items.isEmpty { self.error = "Не удалось загрузить уведомления" }
        }
        isLoading = false
    }

    func loadMoreIfNeeded(current: QNotification) async {
        guard hasMore, !isLoadingMore, !isLoading,
              let index = items.firstIndex(where: { $0.id == current.id }),
              index >= items.count - 5 else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let envelope = try await api.notifications(limit: pageSize, offset: items.count, unreadOnly: unreadOnly)
            let known = Set(items.map(\.id))
            items.append(contentsOf: envelope.items.filter { !known.contains($0.id) })
            hasMore = envelope.items.count == pageSize
        } catch {
            hasMore = false
        }
    }

    func markAllRead(appState: AppState) async {
        do {
            unreadCount = try await api.markNotificationsRead()
            for index in items.indices {
                items[index].isRead = true
            }
            if unreadOnly {
                await load()
            }
            await appState.refreshCounters()
        } catch {
            self.error = (error as? APIError)?.userMessage ?? "Не удалось отметить прочитанными"
        }
    }

    func markRead(_ notification: QNotification, appState: AppState) async {
        guard !notification.isRead else { return }
        if let index = items.firstIndex(where: { $0.id == notification.id }) {
            items[index].isRead = true
        }
        unreadCount = (try? await api.markNotificationsRead(ids: [notification.id])) ?? max(0, unreadCount - 1)
        await appState.refreshCounters()
    }
}

struct NotificationsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.qNavigate) private var navigate
    @StateObject private var model = NotificationsViewModel()

    var body: some View {
        Group {
            if model.isLoading && model.items.isEmpty {
                VStack(spacing: QSpacing.sm) {
                    ForEach(0..<7, id: \.self) { _ in QSkeletonRow(height: 62) }
                }
                .padding(QSpacing.md)
                .frame(maxHeight: .infinity, alignment: .top)
            } else if let error = model.error, model.items.isEmpty {
                QErrorView(message: error) { Task { await model.load() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.items.isEmpty {
                QEmptyState(icon: "bell",
                            title: model.unreadOnly ? "Непрочитанных нет" : "Уведомлений пока нет",
                            subtitle: "Здесь появятся лайки, комментарии и новые подписчики.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: QSpacing.sm) {
                        ForEach(model.items) { item in
                            Button {
                                open(item)
                            } label: {
                                NotificationRow(notification: item)
                            }
                            .buttonStyle(.plain)
                            .task { await model.loadMoreIfNeeded(current: item) }
                        }
                        if model.isLoadingMore {
                            ProgressView().tint(QColor.muted).padding(.vertical, QSpacing.lg)
                        }
                    }
                    .padding(.horizontal, QSpacing.md)
                    .padding(.vertical, QSpacing.sm)
                }
            }
        }
        .background(QColor.bg.ignoresSafeArea())
        .navigationTitle("Уведомления")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        Task { await model.markAllRead(appState: appState) }
                    } label: {
                        Label("Отметить всё прочитанным", systemImage: "checkmark.circle")
                    }
                    .disabled(model.unreadCount == 0)

                    Toggle(isOn: Binding(get: { model.unreadOnly },
                                         set: { newValue in
                                             model.unreadOnly = newValue
                                             Task { await model.load() }
                                         })) {
                        Label("Только непрочитанные", systemImage: "line.3.horizontal.decrease.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundColor(QColor.text)
                }
            }
        }
        .task { await model.load() }
        .onChange(of: model.error) { message in
            guard let message else { return }
            appState.show(QToast(kind: .error, text: message))
            model.error = nil
        }
    }

    private func open(_ notification: QNotification) {
        Task { await model.markRead(notification, appState: appState) }
        if let postID = notification.postID {
            if notification.commentID != nil, notification.kind != .likePost {
                navigate(.comments(postID: postID))
            } else {
                navigate(.post(id: postID))
            }
        } else {
            navigate(.profile(username: notification.actor.username))
        }
    }
}

struct NotificationRow: View {
    let notification: QNotification

    private var tint: Color {
        switch notification.kind {
        case .likePost, .likeComment: return QColor.brand
        case .commentPost, .replyComment: return QColor.info
        case .follow: return QColor.ok
        case .unknown: return QColor.muted
        }
    }

    var body: some View {
        HStack(spacing: QSpacing.md) {
            ZStack(alignment: .bottomTrailing) {
                QAvatar(url: notification.actor.avatarURL, size: 44)
                Image(systemName: notification.kind.icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(tint))
                    .overlay(Circle().strokeBorder(QColor.card, lineWidth: 2))
                    .offset(x: 3, y: 3)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    QUserLabel(displayName: notification.actor.displayName,
                               verified: notification.actor.verified,
                               isPremium: notification.actor.isPremium,
                               premiumEmoji: notification.actor.premiumEmoji,
                               font: QFont.headline(14))
                    Spacer(minLength: 0)
                    if !notification.isRead {
                        Circle().fill(QColor.brand).frame(width: 8, height: 8)
                    }
                }
                Text(notification.actionText)
                    .font(QFont.body(13))
                    .foregroundColor(QColor.text)
                    .lineLimit(2)
                Text(notification.createdDate.map { QDate.relative($0) } ?? notification.createdFmt)
                    .font(QFont.caption(11))
                    .foregroundColor(QColor.muted)
            }
        }
        .padding(QSpacing.md)
        .background(notification.isRead ? QColor.card : QColor.brandSubtle.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous)
                .strokeBorder(notification.isRead ? QColor.line : QColor.brand.opacity(0.3), lineWidth: 1)
        )
    }
}
