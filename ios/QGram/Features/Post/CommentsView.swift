import SwiftUI
import UIKit

@MainActor
final class CommentsViewModel: ObservableObject {
    @Published private(set) var comments: [QComment] = []
    @Published private(set) var total = 0
    @Published private(set) var canComment = false
    @Published private(set) var isLoading = true
    @Published private(set) var isSending = false
    @Published private(set) var expandedIDs: Set<Int> = []
    @Published var draft = ""
    @Published var replyTarget: QComment?
    @Published var error: String?

    let postID: Int
    private let api = APIClient.shared
    private let pageSize = 30
    private var offset = 0
    private var hasMore = true

    init(postID: Int) {
        self.postID = postID
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    func load() async {
        offset = 0
        hasMore = true
        do {
            let envelope = try await api.comments(postID: postID, limit: pageSize, offset: 0)
            comments = envelope.items
            total = envelope.total
            canComment = envelope.canComment
            hasMore = envelope.items.count == pageSize
            error = nil
        } catch is CancellationError {
            // Ignored.
        } catch let error as APIError {
            if comments.isEmpty { self.error = error.userMessage }
        } catch {
            if comments.isEmpty { self.error = "Не удалось загрузить комментарии" }
        }
        isLoading = false
    }

    func loadMoreIfNeeded(current: QComment) async {
        guard hasMore, !isLoading,
              let index = comments.firstIndex(where: { $0.id == current.id }),
              index >= comments.count - 3 else { return }
        let nextOffset = comments.count
        guard nextOffset > offset else { return }
        offset = nextOffset
        do {
            let envelope = try await api.comments(postID: postID, limit: pageSize, offset: nextOffset)
            let known = Set(comments.map(\.id))
            comments.append(contentsOf: envelope.items.filter { !known.contains($0.id) })
            total = envelope.total
            hasMore = envelope.items.count == pageSize
        } catch {
            hasMore = false
        }
    }

    func isExpanded(_ comment: QComment) -> Bool {
        expandedIDs.contains(comment.id)
    }

    /// Loads the replies that did not fit into the preview the list endpoint returns.
    func expandReplies(for comment: QComment) async {
        guard !expandedIDs.contains(comment.id) else {
            expandedIDs.remove(comment.id)
            return
        }
        expandedIDs.insert(comment.id)
        guard comment.replyCount > comment.replies.count else { return }
        do {
            let replies = try await api.replies(commentID: comment.id, limit: 100)
            guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
            comments[index].replies = replies
        } catch {
            self.error = (error as? APIError)?.userMessage ?? "Не удалось загрузить ответы"
        }
    }

    func send(appState: AppState) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let response = try await api.createComment(postID: postID,
                                                       body: text,
                                                       parentID: replyTarget?.id)
            draft = ""
            let parentID = replyTarget?.id
            replyTarget = nil
            total = response.commentCount

            if let parentID, let index = comments.firstIndex(where: { $0.id == parentID }) {
                comments[index].replies.append(response.comment)
                comments[index].replyCount += 1
                expandedIDs.insert(parentID)
            } else {
                comments.insert(response.comment, at: 0)
            }
            appState.contentChanged()
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось отправить комментарий"
        }
    }

    func toggleLike(_ comment: QComment) async {
        do {
            let response = try await APIClient.shared.toggleLike(targetType: "comment", targetID: comment.id)
            apply(liked: response.liked, likeCount: response.likeCount, to: comment.id)
        } catch {
            self.error = (error as? APIError)?.userMessage ?? "Не удалось поставить лайк"
        }
    }

    private func apply(liked: Bool, likeCount: Int, to commentID: Int) {
        if let index = comments.firstIndex(where: { $0.id == commentID }) {
            comments[index].liked = liked
            comments[index].likeCount = likeCount
            return
        }
        for (index, root) in comments.enumerated() {
            if let replyIndex = root.replies.firstIndex(where: { $0.id == commentID }) {
                comments[index].replies[replyIndex].liked = liked
                comments[index].replies[replyIndex].likeCount = likeCount
                return
            }
        }
    }

    func delete(_ comment: QComment, appState: AppState) async {
        do {
            total = try await APIClient.shared.deleteComment(id: comment.id)
            if comment.parentID == nil {
                comments.removeAll { $0.id == comment.id }
            } else {
                for (index, root) in comments.enumerated() where root.replies.contains(where: { $0.id == comment.id }) {
                    comments[index].replies.removeAll { $0.id == comment.id }
                    comments[index].replyCount = max(0, comments[index].replyCount - 1)
                }
            }
            appState.contentChanged()
        } catch {
            self.error = (error as? APIError)?.userMessage ?? "Не удалось удалить комментарий"
        }
    }
}

struct CommentsView: View {
    let postID: Int
    var onCountChanged: ((Int) -> Void)?

    @EnvironmentObject private var appState: AppState
    @Environment(\.qNavigate) private var navigate
    @StateObject private var model: CommentsViewModel
    @FocusState private var inputFocused: Bool
    @State private var pendingDelete: QComment?

    init(postID: Int, onCountChanged: ((Int) -> Void)? = nil) {
        self.postID = postID
        self.onCountChanged = onCountChanged
        _model = StateObject(wrappedValue: CommentsViewModel(postID: postID))
    }

    var body: some View {
        VStack(spacing: 0) {
            list
            composer
        }
        .background(QColor.bg.ignoresSafeArea())
        .navigationTitle("Комментарии")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onChange(of: model.total) { total in
            onCountChanged?(total)
        }
        .onChange(of: model.error) { message in
            guard let message else { return }
            appState.show(QToast(kind: .error, text: message))
            model.error = nil
        }
        .confirmationDialog("Удалить комментарий?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let comment = pendingDelete {
                    Task { await model.delete(comment, appState: appState) }
                }
                pendingDelete = nil
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: QSpacing.md) {
                if model.isLoading && model.comments.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in QSkeletonRow(height: 72) }
                } else if model.comments.isEmpty {
                    QEmptyState(icon: "bubble.left",
                                title: "Комментариев пока нет",
                                subtitle: model.canComment
                                    ? "Будьте первым — напишите что-нибудь."
                                    : "Автор ограничил комментарии.")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 50)
                } else {
                    ForEach(model.comments) { comment in
                        CommentThread(
                            comment: comment,
                            isExpanded: model.isExpanded(comment),
                            onLike: { target in Task { await model.toggleLike(target) } },
                            onReply: { target in
                                model.replyTarget = target
                                inputFocused = true
                            },
                            onDelete: { target in pendingDelete = target },
                            onToggleReplies: { Task { await model.expandReplies(for: comment) } },
                            onOpenProfile: { username in navigate(.profile(username: username)) }
                        )
                        .task { await model.loadMoreIfNeeded(current: comment) }
                    }
                }
            }
            .padding(QSpacing.md)
            .padding(.bottom, QSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.load() }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if let target = model.replyTarget {
                HStack(spacing: QSpacing.sm) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 12))
                        .foregroundColor(QColor.brandLight)
                    Text("Ответ \(target.author.displayName)")
                        .font(QFont.caption(12))
                        .foregroundColor(QColor.brandLight)
                    Text(target.body)
                        .font(QFont.caption(12))
                        .foregroundColor(QColor.muted)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        model.replyTarget = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(QColor.muted)
                    }
                }
                .padding(.horizontal, QSpacing.md)
                .padding(.vertical, 8)
                .background(QColor.card2)
            }

            if model.canComment {
                HStack(alignment: .bottom, spacing: QSpacing.sm) {
                    TextField("Комментарий", text: $model.draft, axis: .vertical)
                        .font(QFont.body(15))
                        .foregroundColor(QColor.textPrimary)
                        .lineLimit(1...5)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(QColor.card2)
                        .clipShape(RoundedRectangle(cornerRadius: QRadius.xl, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: QRadius.xl, style: .continuous)
                                .strokeBorder(inputFocused ? QColor.brand.opacity(0.6) : QColor.line, lineWidth: 1)
                        )
                        .focused($inputFocused)

                    Button {
                        Task { await model.send(appState: appState) }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(model.canSend ? AnyShapeStyle(QColor.brandGradient) : AnyShapeStyle(QColor.card2))
                                .frame(width: 42, height: 42)
                            if model.isSending {
                                ProgressView().tint(.white).controlSize(.small)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(model.canSend ? .white : QColor.muted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canSend)
                }
                .padding(.horizontal, QSpacing.md)
                .padding(.vertical, QSpacing.sm)
            } else if !model.isLoading {
                Text(appState.me == nil ? "Войдите, чтобы комментировать" : "Автор ограничил комментарии")
                    .font(QFont.caption(12))
                    .foregroundColor(QColor.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, QSpacing.md)
            }
        }
        .background(
            QColor.card
                .overlay(QColor.line.frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// A root comment plus its replies.
struct CommentThread: View {
    let comment: QComment
    let isExpanded: Bool
    var onLike: (QComment) -> Void
    var onReply: (QComment) -> Void
    var onDelete: (QComment) -> Void
    var onToggleReplies: () -> Void
    var onOpenProfile: (String) -> Void

    private var visibleReplies: [QComment] {
        isExpanded ? comment.replies : Array(comment.replies.prefix(1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: QSpacing.sm) {
            CommentRow(comment: comment,
                       onLike: { onLike(comment) },
                       onReply: { onReply(comment) },
                       onDelete: { onDelete(comment) },
                       onOpenProfile: { onOpenProfile(comment.author.username) })

            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: QSpacing.sm) {
                    ForEach(visibleReplies) { reply in
                        CommentRow(comment: reply,
                                   isReply: true,
                                   onLike: { onLike(reply) },
                                   onReply: { onReply(reply) },
                                   onDelete: { onDelete(reply) },
                                   onOpenProfile: { onOpenProfile(reply.author.username) })
                    }
                }
                .padding(.leading, 40)
            }

            if comment.replyCount > visibleReplies.count || (isExpanded && comment.replyCount > 1) {
                Button(action: onToggleReplies) {
                    HStack(spacing: 5) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                        Text(isExpanded
                             ? "Свернуть ответы"
                             : "Показать ответы (\(comment.replyCount))")
                    }
                    .font(QFont.caption(12))
                    .foregroundColor(QColor.brandLight)
                }
                .buttonStyle(.plain)
                .padding(.leading, 40)
            }
        }
        .qCard(padding: QSpacing.md)
    }
}

struct CommentRow: View {
    let comment: QComment
    var isReply: Bool = false
    var onLike: () -> Void
    var onReply: () -> Void
    var onDelete: () -> Void
    var onOpenProfile: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: QSpacing.sm) {
            Button(action: onOpenProfile) {
                QAvatar(url: comment.author.avatarURL, size: isReply ? 28 : 34)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    QUserLabel(displayName: comment.author.displayName,
                               verified: comment.author.verified,
                               isPremium: comment.author.isPremium,
                               premiumEmoji: comment.author.premiumEmoji,
                               font: QFont.headline(isReply ? 13 : 14))
                    Text(comment.createdDate.map { QDate.relative($0) } ?? comment.createdFmt)
                        .font(QFont.caption(11))
                        .foregroundColor(QColor.muted)
                    Spacer(minLength: 0)
                }

                Text(comment.body)
                    .font(QFont.body(isReply ? 13 : 14))
                    .foregroundColor(QColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack(spacing: QSpacing.md) {
                    Button(action: onLike) {
                        HStack(spacing: 4) {
                            Image(systemName: comment.liked ? "heart.fill" : "heart")
                                .font(.system(size: 12))
                            if comment.likeCount > 0 {
                                Text("\(comment.likeCount)").font(QFont.caption(11))
                            }
                        }
                        .foregroundColor(comment.liked ? QColor.brand : QColor.muted)
                    }
                    .buttonStyle(.plain)

                    Button(action: onReply) {
                        Text("Ответить")
                            .font(QFont.caption(12))
                            .foregroundColor(QColor.muted)
                    }
                    .buttonStyle(.plain)

                    if comment.canDelete {
                        Button(action: onDelete) {
                            Text("Удалить")
                                .font(QFont.caption(12))
                                .foregroundColor(QColor.danger.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = comment.body
            } label: {
                Label("Скопировать текст", systemImage: "doc.on.doc")
            }
            Button(action: onOpenProfile) {
                Label("Профиль автора", systemImage: "person.crop.circle")
            }
            if comment.canDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
    }
}
