import SwiftUI
import UIKit

struct MessageBubble: View {
    let message: QMessage
    let isMine: Bool
    var onReply: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onReact: (String) -> Void
    var onRetry: () -> Void
    var onDiscard: () -> Void
    var onOpenProfile: () -> Void
    var onOpenAttachment: ([URL], Int) -> Void = { _, _ in }

    static let quickReactions = ["❤️", "🔥", "😂", "👍", "😮", "😢"]

    private var bubbleColor: Color {
        isMine ? QColor.chatMe : QColor.chatOther
    }

    private var textColor: Color {
        isMine ? .white : QColor.chatOtherText
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 44) }

            if !isMine {
                Button(action: onOpenProfile) {
                    QAvatar(url: message.avatarURL, size: 30)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                bubble
                if !message.reactions.isEmpty {
                    reactionsRow
                }
            }

            if !isMine { Spacer(minLength: 44) }
        }
        .padding(.horizontal, QSpacing.md)
        .id(message.id)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reply = message.replyPreview {
                replyPreview(reply)
            }

            if !message.isDeleted, !imageURLs.isEmpty {
                attachmentsGrid
            }

            if message.isDeleted {
                Text("Сообщение удалено")
                    .font(QFont.body(14).italic())
                    .foregroundColor(isMine ? .white.opacity(0.7) : QColor.muted)
            } else if !message.body.isEmpty {
                Text(message.body)
                    .font(QFont.body(15))
                    .foregroundColor(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            HStack(spacing: 4) {
                if message.isEdited {
                    Text("изменено")
                        .font(QFont.caption(10))
                        .foregroundColor(isMine ? .white.opacity(0.65) : QColor.muted)
                }
                Text(QDate.time(message.createdDate))
                    .font(QFont.caption(10))
                    .foregroundColor(isMine ? .white.opacity(0.75) : QColor.muted)
                if isMine {
                    if message.failed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                    } else if message.isPending {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.75))
                    } else {
                        Image(systemName: message.isRead ? "checkmark.circle.fill" : "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(message.isRead ? 1 : 0.7))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(bubbleColor)
        .clipShape(BubbleShape(isMine: isMine))
        .overlay(
            BubbleShape(isMine: isMine)
                .stroke(message.failed ? QColor.danger : Color.clear, lineWidth: 1)
        )
        .frame(maxWidth: 300, alignment: isMine ? .trailing : .leading)
        .contextMenu {
            if message.failed {
                Button {
                    onRetry()
                } label: {
                    Label("Отправить ещё раз", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive, action: onDiscard) {
                    Label("Удалить черновик", systemImage: "trash")
                }
            } else if !message.isDeleted, message.id > 0 {
                ForEach(Self.quickReactions, id: \.self) { reaction in
                    Button {
                        onReact(reaction)
                    } label: {
                        Text("\(reaction)  Реакция")
                    }
                }
                Divider()
                Button(action: onReply) {
                    Label("Ответить", systemImage: "arrowshape.turn.up.left")
                }
                Button {
                    UIPasteboard.general.string = message.body
                } label: {
                    Label("Скопировать", systemImage: "doc.on.doc")
                }
                if isMine {
                    Button(action: onEdit) {
                        Label("Изменить", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
    }

    /// Only images served from qgram.fun are rendered — `attachments` is
    /// free-form JSON that any client could have written.
    private var imageURLs: [URL] {
        message.attachments.compactMap(\.trustedImageURL)
    }

    private var attachmentsGrid: some View {
        VStack(spacing: 4) {
            ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                RemoteImage(url: url)
                    .frame(maxWidth: .infinity)
                    .frame(height: imageURLs.count == 1 ? 200 : 120)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: QRadius.sm, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenAttachment(imageURLs, index) }
            }
        }
        .frame(width: 240)
    }

    private func replyPreview(_ reply: QReplyPreview) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isMine ? Color.white.opacity(0.7) : QColor.brand)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text("@" + reply.username)
                    .font(QFont.caption(11))
                    .foregroundColor(isMine ? .white.opacity(0.9) : QColor.brandLight)
                Text(reply.isDeleted ? "Сообщение удалено" : reply.body)
                    .font(QFont.caption(12))
                    .foregroundColor(isMine ? .white.opacity(0.8) : QColor.muted)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var reactionsRow: some View {
        HStack(spacing: 4) {
            ForEach(message.reactions) { reaction in
                Button {
                    onReact(reaction.reaction)
                } label: {
                    HStack(spacing: 3) {
                        Text(reaction.reaction).font(.system(size: 12))
                        if reaction.count > 1 {
                            Text("\(reaction.count)")
                                .font(QFont.caption(11))
                                .foregroundColor(reaction.me ? QColor.brandLight : QColor.muted)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(reaction.me ? QColor.brandSubtle : QColor.card2)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().strokeBorder(reaction.me ? QColor.brand.opacity(0.5) : QColor.line, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Chat bubble with one squared-off corner on the sender's side.
struct BubbleShape: Shape {
    let isMine: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        let corners: UIRectCorner = isMine
            ? [.topLeft, .topRight, .bottomLeft]
            : [.topLeft, .topRight, .bottomRight]
        return Path(
            UIBezierPath(
                roundedRect: rect,
                byRoundingCorners: corners,
                cornerRadii: CGSize(width: radius, height: radius)
            ).cgPath
        )
    }
}

struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(QColor.muted)
                    .frame(width: 6, height: 6)
                    .scaleEffect(1 + 0.35 * sin(phase + Double(index) * 0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(QColor.chatOther)
        .clipShape(Capsule())
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}
