import SwiftUI

struct PostDetailView: View {
    let postID: Int

    @EnvironmentObject private var appState: AppState
    @Environment(\.qNavigate) private var navigate
    @Environment(\.dismiss) private var dismiss

    @State private var post: QPost?
    @State private var comments: [QComment] = []
    @State private var commentTotal = 0
    @State private var isLoading = true
    @State private var error: String?
    @State private var viewer: ImageViewerPayload?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.md) {
                if isLoading && post == nil {
                    QSkeletonRow(height: 220)
                } else if let error, post == nil {
                    QErrorView(message: error) {
                        Task { await load() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if let post {
                    PostCard(
                        post: post,
                        isDetail: true,
                        onLike: { toggleLike(post) },
                        onDislike: { toggleDislike(post) },
                        onOpenProfile: { navigate(.profile(username: $0)) },
                        onOpenPost: nil,
                        onDelete: { confirmDelete = true },
                        onImageTap: { index in
                            viewer = ImageViewerPayload(urls: post.imageURLs, index: index)
                        }
                    )

                    commentsPreview(post: post)
                }
            }
            .padding(.horizontal, QSpacing.md)
            .padding(.vertical, QSpacing.sm)
        }
        .background(QColor.bg.ignoresSafeArea())
        .navigationTitle("Пост")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: appState.contentRevision) { _ in
            Task { await loadComments() }
        }
        .fullScreenCover(item: $viewer) { payload in
            ImageViewer(urls: payload.urls, startIndex: payload.index)
        }
        .confirmationDialog("Удалить пост?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func commentsPreview(post: QPost) -> some View {
        VStack(alignment: .leading, spacing: QSpacing.md) {
            QSectionHeader(title: "Комментарии", trailing: commentTotal > 0 ? "\(commentTotal)" : nil)

            if comments.isEmpty {
                Text("Комментариев пока нет.")
                    .font(QFont.body(14))
                    .foregroundColor(QColor.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, QSpacing.sm)
            } else {
                ForEach(comments.prefix(3)) { comment in
                    CommentRow(comment: comment,
                               onLike: { like(comment) },
                               onReply: { openComments() },
                               onDelete: { openComments() },
                               onOpenProfile: { navigate(.profile(username: comment.author.username)) })
                }
            }

            Button(action: openComments) {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text(commentTotal > comments.prefix(3).count
                         ? "Все комментарии (\(commentTotal))"
                         : "Написать комментарий")
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12))
                }
            }
            .buttonStyle(QSecondaryButtonStyle(fullWidth: true))
        }
        .qCard()
    }

    private func openComments() {
        navigate(.comments(postID: postID))
    }

    // MARK: - Data

    private func load() async {
        error = nil
        do {
            let loaded = try await APIClient.shared.post(id: postID)
            post = loaded
            commentTotal = loaded.commentCount
            isLoading = false
            await loadComments()
        } catch let apiError as APIError {
            isLoading = false
            if post == nil { error = apiError.userMessage }
        } catch {
            isLoading = false
            if post == nil { self.error = "Не удалось загрузить пост" }
        }
    }

    private func loadComments() async {
        guard let envelope = try? await APIClient.shared.comments(postID: postID, limit: 3, repliesPreview: 0) else {
            return
        }
        comments = envelope.items
        commentTotal = envelope.total
    }

    private func like(_ comment: QComment) {
        Task {
            guard let response = try? await APIClient.shared.toggleLike(targetType: "comment", targetID: comment.id),
                  let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
            comments[index].liked = response.liked
            comments[index].likeCount = response.likeCount
        }
    }

    private func toggleLike(_ post: QPost) {
        Task {
            do {
                self.post = try await PostActions.toggleLike(post)
            } catch {
                appState.showError(error)
            }
        }
    }

    private func toggleDislike(_ post: QPost) {
        Task {
            do {
                self.post = try await PostActions.toggleDislike(post)
            } catch {
                appState.showError(error)
            }
        }
    }

    private func delete() {
        guard let post else { return }
        Task {
            do {
                try await PostActions.delete(post)
                appState.contentChanged()
                appState.show(QToast(kind: .success, text: "Пост удалён"))
                dismiss()
            } catch {
                appState.showError(error)
            }
        }
    }
}
