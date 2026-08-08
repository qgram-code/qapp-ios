import SwiftUI

/// Followers / following list for a profile.
struct FollowListView: View {
    enum Mode: Hashable {
        case followers
        case following

        var title: String {
            switch self {
            case .followers: return "Подписчики"
            case .following: return "Подписки"
            }
        }

        var emptyTitle: String {
            switch self {
            case .followers: return "Подписчиков пока нет"
            case .following: return "Пока ни на кого не подписан"
            }
        }
    }

    let username: String
    let mode: Mode

    @EnvironmentObject private var appState: AppState
    @Environment(\.qNavigate) private var navigate

    @State private var users: [QUser] = []
    @State private var total = 0
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && users.isEmpty {
                VStack(spacing: QSpacing.sm) {
                    ForEach(0..<6, id: \.self) { _ in QSkeletonRow(height: 74) }
                }
                .padding(QSpacing.md)
                .frame(maxHeight: .infinity, alignment: .top)
            } else if let error, users.isEmpty {
                QErrorView(message: error) { Task { await load() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if users.isEmpty {
                QEmptyState(icon: "person.2", title: mode.emptyTitle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: QSpacing.sm) {
                        ForEach(users) { user in
                            UserRow(user: user,
                                    onTap: { navigate(.profile(username: user.username)) })
                                .task { await loadMoreIfNeeded(current: user) }
                        }
                        if isLoadingMore {
                            ProgressView().tint(QColor.muted).padding(.vertical, QSpacing.lg)
                        }
                    }
                    .padding(.horizontal, QSpacing.md)
                    .padding(.vertical, QSpacing.sm)
                }
            }
        }
        .background(QColor.bg.ignoresSafeArea())
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            let envelope = mode == .followers
                ? try await APIClient.shared.followers(username: username, limit: 30, offset: 0)
                : try await APIClient.shared.following(username: username, limit: 30, offset: 0)
            users = envelope.items
            total = envelope.total
            hasMore = envelope.items.count == 30
        } catch is CancellationError {
            // Ignored.
        } catch let apiError as APIError {
            if users.isEmpty { error = apiError.userMessage }
        } catch {
            if users.isEmpty { self.error = "Не удалось загрузить список" }
        }
        isLoading = false
    }

    private func loadMoreIfNeeded(current: QUser) async {
        guard hasMore, !isLoadingMore, !isLoading,
              let index = users.firstIndex(where: { $0.id == current.id }),
              index >= users.count - 3 else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let envelope = mode == .followers
                ? try await APIClient.shared.followers(username: username, limit: 30, offset: users.count)
                : try await APIClient.shared.following(username: username, limit: 30, offset: users.count)
            let known = Set(users.map(\.id))
            users.append(contentsOf: envelope.items.filter { !known.contains($0.id) })
            hasMore = envelope.items.count == 30
        } catch {
            hasMore = false
        }
    }
}
