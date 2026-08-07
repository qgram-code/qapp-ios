import SwiftUI
import UIKit

struct PostCard: View {
    let post: QPost
    var isDetail: Bool = false
    var onLike: () -> Void
    var onDislike: () -> Void
    var onOpenProfile: (String) -> Void
    var onOpenPost: (() -> Void)?
    var onDelete: (() -> Void)?
    var onImageTap: ((Int) -> Void)?

    @EnvironmentObject private var appState: AppState

    private var isMine: Bool { appState.me?.id == post.author.id }

    var body: some View {
        VStack(alignment: .leading, spacing: QSpacing.md) {
            header

            if !post.content.isEmpty {
                Text(post.content)
                    .font(QFont.body(15))
                    .foregroundColor(QColor.text)
                    .lineLimit(isDetail ? nil : 12)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if !post.imageURLs.isEmpty {
                PostImagesView(urls: post.imageURLs) { index in
                    onImageTap?(index)
                }
            }

            actions
        }
        .qCard()
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenPost?()
        }
        .contextMenu {
            Button {
                onOpenProfile(post.author.username)
            } label: {
                Label("Профиль автора", systemImage: "person.crop.circle")
            }
            Button {
                UIPasteboard.general.string = PostActions.webURL(for: post).absoluteString
                appState.show(QToast(kind: .success, text: "Ссылка скопирована"))
            } label: {
                Label("Скопировать ссылку", systemImage: "link")
            }
            if !post.content.isEmpty {
                Button {
                    UIPasteboard.general.string = post.content
                    appState.show(QToast(kind: .success, text: "Текст скопирован"))
                } label: {
                    Label("Скопировать текст", systemImage: "doc.on.doc")
                }
            }
            if isMine, let onDelete {
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Удалить пост", systemImage: "trash")
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: QSpacing.md) {
            Button {
                onOpenProfile(post.author.username)
            } label: {
                QAvatar(url: post.author.avatarURL, size: 42, ring: post.author.isPremium)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                QUserLabel(displayName: post.author.displayName,
                           verified: post.author.verified,
                           isPremium: post.author.isPremium,
                           premiumEmoji: post.author.premiumEmoji)
                HStack(spacing: 6) {
                    Text(post.createdDate.map { QDate.relative($0) } ?? post.createdFmt)
                        .font(QFont.caption(12))
                        .foregroundColor(QColor.muted)
                    if post.isPrivate {
                        Label("Только для своих", systemImage: "lock.fill")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 11))
                            .foregroundColor(QColor.warn)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var actions: some View {
        HStack(spacing: QSpacing.sm) {
            ReactionButton(icon: post.liked ? "heart.fill" : "heart",
                           count: post.likeCount,
                           tint: post.liked ? QColor.brand : QColor.muted,
                           active: post.liked,
                           action: onLike)

            ReactionButton(icon: post.disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                           count: post.dislikeCount,
                           tint: post.disliked ? QColor.danger : QColor.muted,
                           active: post.disliked,
                           action: onDislike)

            ReactionButton(icon: "bubble.right",
                           count: post.commentCount,
                           tint: QColor.muted,
                           active: false) {
                onOpenPost?()
            }

            Spacer(minLength: 0)

            ShareLink(item: PostActions.webURL(for: post)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(QColor.muted)
                    .frame(width: 34, height: 30)
            }
        }
    }
}

struct ReactionButton: View {
    let icon: String
    let count: Int
    let tint: Color
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(QFont.caption(13))
                        .contentTransition(.numericText())
                }
            }
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(active ? QColor.brandSubtle : QColor.card2)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: active)
        .animation(.easeOut(duration: 0.18), value: count)
    }
}

/// 1–5 images laid out the way the web feed does: single image keeps its aspect,
/// multiples become an even grid.
struct PostImagesView: View {
    let urls: [URL]
    var onTap: (Int) -> Void

    var body: some View {
        switch urls.count {
        case 0:
            EmptyView()
        case 1:
            imageTile(0)
                .frame(maxWidth: .infinity)
                .frame(height: 260)
        case 2:
            HStack(spacing: 4) {
                imageTile(0)
                imageTile(1)
            }
            .frame(height: 200)
        case 3:
            HStack(spacing: 4) {
                imageTile(0)
                VStack(spacing: 4) {
                    imageTile(1)
                    imageTile(2)
                }
            }
            .frame(height: 220)
        default:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, _ in
                    imageTile(index)
                        .frame(height: 130)
                }
            }
        }
    }

    private func imageTile(_ index: Int) -> some View {
        RemoteImage(url: urls[index])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: QRadius.md, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { onTap(index) }
    }
}
