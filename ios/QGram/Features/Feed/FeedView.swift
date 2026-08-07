import SwiftUI
import UIKit

struct FeedView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.qNavigate) private var navigate
    @StateObject private var model = FeedViewModel()

    @State private var showCompose = false
    @State private var viewer: ImageViewerPayload?
    @State private var pendingDelete: QPost?
    @State private var lastRevision = 0

    var body: some View {
        ScrollView {
            LazyVStack(spacing: QSpacing.md) {
                if model.isLoading && model.posts.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in
                        QSkeletonRow(height: 190)
                    }
                } else if let error = model.error, model.posts.isEmpty {
                    QErrorView(message: error) {
                        Task { await model.refresh() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if model.isEmpty {
                    QEmptyState(icon: "square.stack.3d.up",
                                title: "Пока пусто",
                                subtitle: "Здесь появятся посты. Напишите первый — кнопка внизу справа.",
                                actionTitle: "Создать пост") {
                        showCompose = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    ForEach(model.posts) { post in
                        PostCard(
                            post: post,
                            onLike: { like(post) },
                            onDislike: { dislike(post) },
                            onOpenProfile: { username in openProfile(username) },
                            onOpenPost: { openPost(post) },
                            onDelete: { pendingDelete = post },
                            onImageTap: { index in
                                viewer = ImageViewerPayload(urls: post.imageURLs, index: index)
                            }
                        )
                        .task {
                            await model.loadMoreIfNeeded(currentItem: post)
                        }
                    }

                    if model.isLoadingMore {
                        ProgressView()
                            .tint(QColor.muted)
                            .padding(.vertical, QSpacing.lg)
                    } else if !model.hasMore {
                        Text("Вы посмотрели всю ленту")
                            .font(QFont.caption(12))
                            .foregroundColor(QColor.muted)
                            .padding(.vertical, QSpacing.lg)
                    }
                }
            }
            .padding(.horizontal, QSpacing.md)
            .padding(.top, QSpacing.sm)
            .padding(.bottom, 96)
        }
        .background(QColor.bg.ignoresSafeArea())
        .refreshable { await model.refresh() }
        .navigationTitle("Лента")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 8) {
                    QLogoMark(size: 26)
                    Text("qgram")
                        .font(QFont.headline(17))
                        .foregroundColor(QColor.textPrimary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    navigate(.notifications)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: appState.unreadNotifications > 0 ? "bell.badge.fill" : "bell")
                            .foregroundColor(appState.unreadNotifications > 0 ? QColor.brandLight : QColor.text)
                            .frame(width: 30, height: 30)
                        if appState.unreadNotifications > 0 {
                            QBadge(count: appState.unreadNotifications)
                                .offset(x: 10, y: -4)
                        }
                    }
                }
                .accessibilityLabel("Уведомления")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            ComposeFAB { showCompose = true }
                .padding(.trailing, QSpacing.lg)
                .padding(.bottom, QSpacing.lg)
        }
        .sheet(isPresented: $showCompose) {
            ComposeView { post in
                model.prepend(post)
                appState.contentChanged()
                appState.show(QToast(kind: .success, text: "Пост опубликован"))
            }
            .environmentObject(appState)
        }
        .fullScreenCover(item: $viewer) { payload in
            ImageViewer(urls: payload.urls, startIndex: payload.index)
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
        } message: {
            Text("Пост будет удалён без возможности восстановления.")
        }
        .task {
            await model.loadInitial()
            lastRevision = appState.contentRevision
        }
        .onChange(of: appState.contentRevision) { revision in
            guard revision != lastRevision else { return }
            lastRevision = revision
            Task { await model.refresh() }
        }
    }

    // MARK: - Actions

    private func like(_ post: QPost) {
        Task {
            do {
                model.replace(try await PostActions.toggleLike(post))
            } catch {
                appState.showError(error)
            }
        }
    }

    private func dislike(_ post: QPost) {
        Task {
            do {
                model.replace(try await PostActions.toggleDislike(post))
            } catch {
                appState.showError(error)
            }
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

    private func openProfile(_ username: String) {
        navigate(.profile(username: username))
    }

    private func openPost(_ post: QPost) {
        navigate(.post(id: post.id))
    }
}

struct ImageViewerPayload: Identifiable {
    let id = UUID()
    let urls: [URL]
    let index: Int
}

struct ComposeFAB: View {
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 58, height: 58)
                .background(QColor.brandGradient)
                .clipShape(Circle())
                .shadow(color: QColor.brand.opacity(0.45), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Создать пост")
    }
}
