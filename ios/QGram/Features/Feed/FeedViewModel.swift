import SwiftUI

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var posts: [QPost] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var error: String?

    private let api = APIClient.shared
    private let pageSize = 20
    private var loadTask: Task<Void, Never>?

    var isEmpty: Bool { posts.isEmpty && !isLoading && error == nil }

    func loadInitial(force: Bool = false) async {
        if !force, !posts.isEmpty { return }
        await refresh()
    }

    func refresh() async {
        loadTask?.cancel()
        isLoading = posts.isEmpty
        error = nil
        do {
            let items = try await api.feed(limit: pageSize, offset: 0)
            posts = items
            hasMore = items.count == pageSize
        } catch is CancellationError {
            // Superseded by a newer load.
        } catch let error as APIError {
            if posts.isEmpty { self.error = error.userMessage }
        } catch {
            if posts.isEmpty { self.error = "Не удалось загрузить ленту" }
        }
        isLoading = false
    }

    func loadMoreIfNeeded(currentItem: QPost) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        // Trigger when the last few cards become visible.
        guard let index = posts.firstIndex(where: { $0.id == currentItem.id }),
              index >= posts.count - 3 else { return }
        await loadMore()
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let items = try await api.feed(limit: pageSize, offset: posts.count)
            // Offset paging can repeat rows when new posts land mid-scroll.
            let known = Set(posts.map(\.id))
            let fresh = items.filter { !known.contains($0.id) }
            posts.append(contentsOf: fresh)
            hasMore = items.count == pageSize
        } catch is CancellationError {
            // Ignored.
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

    func prepend(_ post: QPost) {
        posts.removeAll { $0.id == post.id }
        posts.insert(post, at: 0)
    }
}

/// Like / dislike / delete shared by the feed, the profile and the post screen.
@MainActor
enum PostActions {
    static func toggleLike(_ post: QPost) async throws -> QPost {
        let response = try await APIClient.shared.toggleLike(targetType: "post", targetID: post.id)
        var updated = post
        updated.liked = response.liked
        updated.likeCount = response.likeCount
        if let disliked = response.disliked { updated.disliked = disliked }
        if let dislikeCount = response.dislikeCount { updated.dislikeCount = dislikeCount }
        return updated
    }

    static func toggleDislike(_ post: QPost) async throws -> QPost {
        let response = try await APIClient.shared.toggleDislike(postID: post.id)
        var updated = post
        updated.liked = response.liked
        updated.likeCount = response.likeCount
        updated.disliked = response.disliked
        updated.dislikeCount = response.dislikeCount
        return updated
    }

    static func delete(_ post: QPost) async throws {
        try await APIClient.shared.deletePost(id: post.id)
    }

    static func webURL(for post: QPost) -> URL {
        AppConfig.websiteURL.appendingPathComponent("post/\(post.id)")
    }
}
