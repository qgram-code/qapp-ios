import SwiftUI

struct ProfileView: View {
    let username: String
    var isRoot: Bool = false

    @EnvironmentObject private var appState: AppState
    @Environment(\.qNavigate) private var navigate
    @StateObject private var model = ProfileViewModel()

    @State private var viewer: ImageViewerPayload?
    @State private var pendingDelete: QPost?
    @State private var showEditor = false
    @State private var isStartingChat = false
    @State private var isTogglingFollow = false
    @State private var lastRevision = 0

    private var isMe: Bool {
        guard let me = appState.me else { return false }
        return me.username.lowercased() == username.lowercased()
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: QSpacing.md) {
                if let user = model.user {
                    ProfileHeader(user: user,
                                  presence: model.presence,
                                  isMe: isMe,
                                  isStartingChat: isStartingChat,
                                  isTogglingFollow: isTogglingFollow,
                                  onMessage: { startChat(with: user) },
                                  onToggleFollow: { toggleFollow(user) },
                                  onOpenFollowers: { navigate(.followers(username: user.username)) },
                                  onOpenFollowing: { navigate(.following(username: user.username)) },
                                  onEdit: { showEditor = true },
                                  onOpenBanner: {
                                      if let url = user.bannerURL {
                                          viewer = ImageViewerPayload(urls: [url], index: 0)
                                      }
                                  },
                                  onOpenAvatar: {
                                      if let url = user.avatarURL {
                                          viewer = ImageViewerPayload(urls: [url], index: 0)
                                      }
                                  })
                } else if model.isLoading {
                    QSkeletonRow(height: 220)
                } else if let error = model.error {
                    QErrorView(message: error) {
                        Task { await model.load() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }

                if model.user != nil {
                    if model.posts.isEmpty && !model.isLoading {
                        QEmptyState(icon: "tray",
                                    title: isMe ? "У вас пока нет постов" : "Постов пока нет",
                                    subtitle: isMe ? "Опубликуйте первый пост из ленты." : "")
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(model.posts) { post in
                            PostCard(
                                post: post,
                                onLike: { like(post) },
                                onDislike: { dislike(post) },
                                onOpenProfile: { navigate(.profile(username: $0)) },
                                onOpenPost: { navigate(.post(id: post.id)) },
                                onDelete: { pendingDelete = post },
                                onImageTap: { index in
                                    viewer = ImageViewerPayload(urls: post.imageURLs, index: index)
                                }
                            )
                            .task { await model.loadMoreIfNeeded(currentItem: post) }
                        }
                        if model.isLoadingMore {
                            ProgressView().tint(QColor.muted).padding(.vertical, QSpacing.lg)
                        }
                    }
                }
            }
            .padding(.horizontal, QSpacing.md)
            .padding(.top, QSpacing.sm)
            .padding(.bottom, 90)
        }
        .background(QColor.bg.ignoresSafeArea())
        .navigationTitle(model.user?.displayName ?? "@\(username)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isMe {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        navigate(.settings)
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(QColor.text)
                    }
                }
            }
        }
        .refreshable { await model.load() }
        .task(id: username) {
            model.configure(username: username)
            await model.load()
            lastRevision = appState.contentRevision
        }
        .onChange(of: appState.contentRevision) { revision in
            guard revision != lastRevision else { return }
            lastRevision = revision
            Task { await model.load() }
        }
        .fullScreenCover(item: $viewer) { payload in
            ImageViewer(urls: payload.urls, startIndex: payload.index)
        }
        .sheet(isPresented: $showEditor) {
            EditProfileView { updated in
                model.apply(user: updated)
                appState.updateMe(updated)
            }
            .environmentObject(appState)
        }
        .confirmationDialog("Удалить пост?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let post = pendingDelete { delete(post) }
                pendingDelete = nil
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil }
        }
    }

    // MARK: - Actions

    private func like(_ post: QPost) {
        Task {
            do { model.replace(try await PostActions.toggleLike(post)) }
            catch { appState.showError(error) }
        }
    }

    private func dislike(_ post: QPost) {
        Task {
            do { model.replace(try await PostActions.toggleDislike(post)) }
            catch { appState.showError(error) }
        }
    }

    private func delete(_ post: QPost) {
        Task {
            do {
                try await PostActions.delete(post)
                model.remove(id: post.id)
                appState.contentChanged()
                appState.show(QToast(kind: .success, text: "Пост удалён"))
            } catch {
                appState.showError(error)
            }
        }
    }

    private func toggleFollow(_ user: QUser) {
        guard !isTogglingFollow else { return }
        isTogglingFollow = true
        Task {
            defer { isTogglingFollow = false }
            do {
                let response = (user.isFollowing ?? false)
                    ? try await APIClient.shared.unfollow(username: user.username)
                    : try await APIClient.shared.follow(username: user.username)
                var updated = user
                updated.isFollowing = response.isFollowing
                updated.followersCount = response.followersCount
                updated.followingCount = response.followingCount
                model.apply(user: updated)
            } catch {
                appState.showError(error)
            }
        }
    }

    private func startChat(with user: QUser) {
        guard !isStartingChat else { return }
        isStartingChat = true
        Task {
            defer { isStartingChat = false }
            do {
                let response = try await APIClient.shared.startChat(username: user.username)
                navigate(.chat(convID: response.convID, title: user.displayName))
            } catch {
                appState.showError(error)
            }
        }
    }
}

/// Banner + avatar + stats block, shared by your own profile and other users'.
struct ProfileHeader: View {
    let user: QUser
    let presence: QPresence
    let isMe: Bool
    var isStartingChat: Bool = false
    var isTogglingFollow: Bool = false
    var onMessage: () -> Void
    var onToggleFollow: () -> Void
    var onOpenFollowers: () -> Void
    var onOpenFollowing: () -> Void
    var onEdit: () -> Void
    var onOpenBanner: () -> Void
    var onOpenAvatar: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if user.bannerURL != nil {
                        RemoteImage(url: user.bannerURL)
                            .frame(height: 132)
                            .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onOpenBanner)
                    } else {
                        QColor.brandGradient
                            .frame(height: 132)
                            .opacity(0.75)
                    }
                }
                .frame(maxWidth: .infinity)

                ZStack(alignment: .bottomTrailing) {
                    QAvatar(url: user.avatarURL, size: 84, ring: user.isPremium)
                        .background(Circle().fill(QColor.card).frame(width: 92, height: 92))
                        .onTapGesture(perform: onOpenAvatar)
                    QPresenceDot(presence: presence, size: 16)
                        .offset(x: 2, y: -4)
                }
                .padding(.leading, QSpacing.lg)
                .offset(y: 42)
            }
            .frame(height: 132)

            VStack(alignment: .leading, spacing: QSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        QUserLabel(displayName: user.displayName,
                                   verified: user.verified,
                                   isPremium: user.isPremium,
                                   premiumEmoji: user.premiumEmoji,
                                   premiumColor: user.premiumColor,
                                   font: QFont.title(20))
                        HStack(spacing: 6) {
                            Text(user.handle)
                                .font(QFont.caption(13))
                                .foregroundColor(QColor.muted)
                            Text("·").foregroundColor(QColor.muted)
                            Text(presence.title)
                                .font(QFont.caption(13))
                                .foregroundColor(presence.isOnline ? QColor.ok : QColor.muted)
                        }
                    }
                    Spacer()
                }

                if user.isFrozen || user.isBanned {
                    HStack(spacing: 6) {
                        Image(systemName: user.isBanned ? "nosign" : "snowflake")
                        Text(user.isBanned ? "Аккаунт заблокирован" : "Аккаунт заморожен")
                    }
                    .font(QFont.caption(12))
                    .foregroundColor(QColor.danger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(QColor.dangerSubtle)
                    .clipShape(Capsule())
                }

                if !user.bio.isEmpty {
                    Text(user.bio)
                        .font(QFont.body(14))
                        .foregroundColor(QColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: QSpacing.xl) {
                    Button(action: onOpenFollowers) {
                        stat(user.followersCount ?? 0, "подписчиков")
                    }
                    .buttonStyle(.plain)
                    Button(action: onOpenFollowing) {
                        stat(user.followingCount ?? 0, "подписок")
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }

                if isMe {
                    Button("Редактировать профиль", action: onEdit)
                        .buttonStyle(QSecondaryButtonStyle(fullWidth: true))
                } else {
                    HStack(spacing: QSpacing.sm) {
                        Button(action: onToggleFollow) {
                            HStack(spacing: 6) {
                                if isTogglingFollow {
                                    ProgressView().tint(.white).controlSize(.small)
                                } else {
                                    Image(systemName: (user.isFollowing ?? false) ? "checkmark" : "plus")
                                }
                                Text((user.isFollowing ?? false) ? "Вы подписаны" : "Подписаться")
                            }
                        }
                        .buttonStyle(
                            (user.isFollowing ?? false)
                                ? AnyButtonStyle(QSecondaryButtonStyle(fullWidth: true))
                                : AnyButtonStyle(QPrimaryButtonStyle())
                        )
                        .disabled(isTogglingFollow)

                        Button(action: onMessage) {
                            if isStartingChat {
                                ProgressView().tint(QColor.text).controlSize(.small)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                        }
                        .buttonStyle(QIconButtonStyle(size: 44))
                        .foregroundColor(QColor.text)
                        .disabled(isStartingChat)
                    }
                }
            }
            .padding(.top, 52)
            .padding(.horizontal, QSpacing.lg)
            .padding(.bottom, QSpacing.lg)
        }
        .background(QColor.card)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous)
                .strokeBorder(QColor.line, lineWidth: 1)
        )
    }

    private func stat(_ value: Int, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(QFont.headline(17))
                .foregroundColor(QColor.textPrimary)
            Text(title)
                .font(QFont.caption(11))
                .foregroundColor(QColor.muted)
        }
    }
}

/// The profile tab: your own profile, or a prompt to retry when `/api/me`
/// failed during a cold, offline launch.
struct MyProfileView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if let me = appState.me {
                ProfileView(username: me.username, isRoot: true)
            } else {
                VStack(spacing: QSpacing.lg) {
                    QErrorView(message: "Не удалось загрузить ваш профиль.") {
                        Task { await appState.refreshMe() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(QColor.bg.ignoresSafeArea())
                .navigationTitle("Профиль")
                .task { await appState.refreshMe() }
            }
        }
    }
}
