import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    enum Scope: String, CaseIterable, Identifiable {
        case all
        case users
        case posts

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "Всё"
            case .users: return "Люди"
            case .posts: return "Посты"
            }
        }
    }

    @Published var query = ""
    @Published var scope: Scope = .all
    @Published private(set) var users: [QUser] = []
    @Published private(set) var posts: [QPost] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasSearched = false
    @Published var error: String?

    private var searchTask: Task<Void, Never>?

    var isEmptyResult: Bool { users.isEmpty && posts.isEmpty }

    /// Debounced search — the endpoint runs a LIKE query, so we do not fire it
    /// on every keystroke.
    func queryChanged() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 1 else {
            users = []
            posts = []
            hasSearched = false
            isSearching = false
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.run()
        }
    }

    func run() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !text.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let envelope = try await APIClient.shared.search(query: text, limit: 25, scope: scope.rawValue)
            users = envelope.users
            posts = envelope.posts
            hasSearched = true
            error = nil
        } catch is CancellationError {
            // Superseded.
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось выполнить поиск"
        }
    }

    func setFollowing(_ isFollowing: Bool, for username: String) {
        guard let index = users.firstIndex(where: { $0.username == username }) else { return }
        users[index].isFollowing = isFollowing
        let delta = isFollowing ? 1 : -1
        users[index].followersCount = max(0, (users[index].followersCount ?? 0) + delta)
    }
}

struct SearchView: View {
    /// When set, tapping a person hands them back instead of opening a profile
    /// (used by "new chat").
    var onPickUser: ((QUser) -> Void)?

    @EnvironmentObject private var appState: AppState
    @Environment(\.qNavigate) private var navigate
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SearchViewModel()
    @FocusState private var focused: Field?

    private enum Field {
        case query
    }

    var body: some View {
        VStack(spacing: QSpacing.md) {
            searchField

            // When picking someone for a new chat, posts are noise.
            if onPickUser == nil {
                Picker("", selection: $model.scope) {
                    ForEach(SearchViewModel.Scope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, QSpacing.md)
                .onChange(of: model.scope) { _ in
                    Task { await model.run() }
                }
            }

            content
        }
        .padding(.top, QSpacing.sm)
        .background(QColor.bg.ignoresSafeArea())
        .navigationTitle("Поиск")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.query) { _ in model.queryChanged() }
        .onChange(of: model.error) { message in
            guard let message else { return }
            appState.show(QToast(kind: .error, text: message))
            model.error = nil
        }
        .task {
            if onPickUser != nil { model.scope = .users }
            try? await Task.sleep(nanoseconds: 250_000_000)
            focused = .query
        }
    }

    private var searchField: some View {
        HStack(spacing: QSpacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(QColor.muted)
                TextField("Люди и посты", text: $model.query)
                    .font(QFont.body(16))
                    .foregroundColor(QColor.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.search)
                    .focused($focused, equals: .query)
                    .onSubmit { Task { await model.run() } }
                if model.isSearching {
                    ProgressView().controlSize(.small)
                } else if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(QColor.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(QColor.card2)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.md, style: .continuous)
                    .strokeBorder(focused == .query ? QColor.brand : QColor.line, lineWidth: 1)
            )

            if onPickUser != nil {
                Button("Отмена") { dismiss() }
                    .font(QFont.body(15))
                    .foregroundColor(QColor.muted)
            }
        }
        .padding(.horizontal, QSpacing.md)
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasSearched && model.query.isEmpty {
            QEmptyState(icon: "magnifyingglass",
                        title: "Найдите людей и посты",
                        subtitle: "Введите часть имени пользователя или слово из поста.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.hasSearched && model.isEmptyResult && !model.isSearching {
            QEmptyState(icon: "questionmark.circle",
                        title: "Ничего не найдено",
                        subtitle: "Попробуйте другой запрос.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: QSpacing.md) {
                    if !model.users.isEmpty {
                        QSectionHeader(title: "Люди", trailing: "\(model.users.count)")
                            .padding(.horizontal, QSpacing.xs)
                        ForEach(model.users) { user in
                            UserRow(user: user,
                                    showFollowButton: onPickUser == nil && user.id != appState.me?.id,
                                    onTap: { pick(user) },
                                    onFollowChanged: { isFollowing in
                                        model.setFollowing(isFollowing, for: user.username)
                                    })
                        }
                    }

                    if !model.posts.isEmpty {
                        QSectionHeader(title: "Посты", trailing: "\(model.posts.count)")
                            .padding(.horizontal, QSpacing.xs)
                            .padding(.top, model.users.isEmpty ? 0 : QSpacing.sm)
                        ForEach(model.posts) { post in
                            Button {
                                navigate(.post(id: post.id))
                            } label: {
                                SearchPostRow(post: post)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, QSpacing.md)
                .padding(.bottom, QSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func pick(_ user: QUser) {
        if let onPickUser {
            onPickUser(user)
            dismiss()
        } else {
            navigate(.profile(username: user.username))
        }
    }
}

/// A person row with an inline follow button — reused by search and follow lists.
struct UserRow: View {
    let user: QUser
    var showFollowButton: Bool = true
    var onTap: () -> Void
    var onFollowChanged: ((Bool) -> Void)?

    @EnvironmentObject private var appState: AppState
    @State private var isFollowing: Bool
    @State private var isBusy = false

    init(user: QUser, showFollowButton: Bool = true, onTap: @escaping () -> Void,
         onFollowChanged: ((Bool) -> Void)? = nil) {
        self.user = user
        self.showFollowButton = showFollowButton
        self.onTap = onTap
        self.onFollowChanged = onFollowChanged
        _isFollowing = State(initialValue: user.isFollowing ?? false)
    }

    var body: some View {
        HStack(spacing: QSpacing.md) {
            Button(action: onTap) {
                HStack(spacing: QSpacing.md) {
                    QAvatar(url: user.avatarURL, size: 46, ring: user.isPremium)
                    VStack(alignment: .leading, spacing: 2) {
                        QUserLabel(displayName: user.displayName,
                                   verified: user.verified,
                                   isPremium: user.isPremium,
                                   premiumEmoji: user.premiumEmoji,
                                   premiumColor: user.premiumColor,
                                   font: QFont.headline(15))
                        if !user.bio.isEmpty {
                            Text(user.bio)
                                .font(QFont.caption(12))
                                .foregroundColor(QColor.muted)
                                .lineLimit(1)
                        } else {
                            Text(user.handle)
                                .font(QFont.caption(12))
                                .foregroundColor(QColor.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showFollowButton, user.id != appState.me?.id {
                Button {
                    Task { await toggle() }
                } label: {
                    Group {
                        if isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(isFollowing ? "Вы подписаны" : "Подписаться")
                                .font(QFont.caption(12))
                        }
                    }
                    .foregroundColor(isFollowing ? QColor.muted : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background {
                        if isFollowing {
                            QColor.card2
                        } else {
                            QColor.brandGradient
                        }
                    }
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(isFollowing ? QColor.line : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
        .padding(QSpacing.md)
        .background(QColor.card)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous)
                .strokeBorder(QColor.line, lineWidth: 1)
        )
    }

    private func toggle() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let response = isFollowing
                ? try await APIClient.shared.unfollow(username: user.username)
                : try await APIClient.shared.follow(username: user.username)
            isFollowing = response.isFollowing
            onFollowChanged?(response.isFollowing)
        } catch {
            appState.showError(error)
        }
    }
}

struct SearchPostRow: View {
    let post: QPost

    var body: some View {
        HStack(alignment: .top, spacing: QSpacing.md) {
            if let url = post.imageURLs.first {
                RemoteImage(url: url)
                    .frame(width: 56, height: 56)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: QRadius.sm, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                QUserLabel(displayName: post.author.displayName,
                           verified: post.author.verified,
                           isPremium: post.author.isPremium,
                           premiumEmoji: post.author.premiumEmoji,
                           font: QFont.headline(14))
                Text(post.content)
                    .font(QFont.body(13))
                    .foregroundColor(QColor.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack(spacing: QSpacing.md) {
                    Label("\(post.likeCount)", systemImage: "heart")
                    Label("\(post.commentCount)", systemImage: "bubble.right")
                    Text(post.createdDate.map { QDate.relative($0) } ?? post.createdFmt)
                }
                .font(QFont.caption(11))
                .foregroundColor(QColor.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(QSpacing.md)
        .background(QColor.card)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous)
                .strokeBorder(QColor.line, lineWidth: 1)
        )
    }
}
