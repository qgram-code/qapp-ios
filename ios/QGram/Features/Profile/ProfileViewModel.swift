import SwiftUI

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var user: QUser?
    @Published private(set) var posts: [QPost] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published private(set) var presence: QPresence = .offline
    @Published var error: String?

    private let api = APIClient.shared
    private let pageSize = 20
    private(set) var username: String = ""

    func configure(username: String) {
        guard self.username != username else { return }
        self.username = username
        user = nil
        posts = []
        hasMore = true
    }

    func load() async {
        guard !username.isEmpty else { return }
        isLoading = user == nil
        error = nil
        do {
            let envelope = try await api.profile(username: username, includePosts: true, limit: pageSize)
            user = envelope.profile
            posts = envelope.posts
            hasMore = envelope.posts.count == pageSize
            presence = (try? await api.presence(username: username)) ?? .offline
        } catch is CancellationError {
            // Ignored.
        } catch let error as APIError {
            if user == nil { self.error = error.userMessage }
        } catch {
            if user == nil { self.error = "Не удалось загрузить профиль" }
        }
        isLoading = false
    }

    func loadMoreIfNeeded(currentItem: QPost) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        guard let index = posts.firstIndex(where: { $0.id == currentItem.id }),
              index >= posts.count - 3 else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let items = try await api.userPosts(username: username, limit: pageSize, offset: posts.count)
            let known = Set(posts.map(\.id))
            posts.append(contentsOf: items.filter { !known.contains($0.id) })
            hasMore = items.count == pageSize
        } catch {
            hasMore = false
        }
    }

    func replace(_ post: QPost) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[index] = post
    }

    func remove(id: Int) {
        posts.removeAll { $0.id == id }
    }

    func apply(user: QUser) {
        self.user = user
    }
}
