import SwiftUI
import PhotosUI

struct ChatView: View {
    let convID: Int
    var initialTitle: String = ""

    @EnvironmentObject private var appState: AppState
    @Environment(\.qNavigate) private var navigate
    @StateObject private var model: ChatViewModel

    @State private var pendingDelete: QMessage?
    @State private var isPinnedToBottom = true
    @State private var pickerItem: PhotosPickerItem?
    @State private var viewer: ImageViewerPayload?
    @FocusState private var inputFocused: Bool

    init(convID: Int, initialTitle: String = "") {
        self.convID = convID
        self.initialTitle = initialTitle
        _model = StateObject(wrappedValue: ChatViewModel(convID: convID))
    }

    private var myID: Int { appState.me?.id ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            composer
        }
        .background(QColor.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { header }
        }
        .task {
            await model.start()
            await appState.refreshCounters()
        }
        .onDisappear {
            model.stop()
            Task { await appState.refreshCounters() }
        }
        .onChange(of: model.error) { message in
            guard let message else { return }
            appState.show(QToast(kind: .error, text: message))
            model.error = nil
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                defer { pickerItem = nil }
                guard let image = await ImagePreparation.prepare(item, maxDimension: 2048,
                                                                 maxMB: AppConfig.chatAttachmentMaxMB) else {
                    appState.show(QToast(kind: .error, text: "Не удалось подготовить изображение"))
                    return
                }
                await model.attach(image)
            }
        }
        .fullScreenCover(item: $viewer) { payload in
            ImageViewer(urls: payload.urls, startIndex: payload.index)
        }
        .confirmationDialog("Удалить сообщение?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let message = pendingDelete {
                    Task { await model.delete(message) }
                }
                pendingDelete = nil
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil }
        }
    }

    // MARK: - Header

    private var header: some View {
        Button {
            if let username = model.other?.username {
                navigate(.profile(username: username))
            }
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    QAvatar(url: model.other?.avatarURL, size: 32)
                    QPresenceDot(presence: model.presence, size: 10)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.other?.displayName ?? initialTitle)
                        .font(QFont.headline(15))
                        .foregroundColor(QColor.textPrimary)
                        .lineLimit(1)
                    Text(model.isTypingRemote ? "печатает…" : model.presence.title)
                        .font(QFont.caption(11))
                        .foregroundColor(model.isTypingRemote ? QColor.brandLight : QColor.muted)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.other == nil)
    }

    // MARK: - Messages

    private var messagesList: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if model.hasMoreBefore {
                            Button {
                                Task { await model.loadOlder() }
                            } label: {
                                if model.isLoadingOlder {
                                    ProgressView().tint(QColor.muted)
                                } else {
                                    Text("Показать более ранние сообщения")
                                        .font(QFont.caption(12))
                                        .foregroundColor(QColor.brandLight)
                                }
                            }
                            .padding(.vertical, QSpacing.md)
                        }

                        if model.isLoading && model.messages.isEmpty {
                            ForEach(0..<5, id: \.self) { _ in
                                QSkeletonRow(height: 44)
                                    .padding(.horizontal, QSpacing.md)
                            }
                        } else if model.messages.isEmpty {
                            QEmptyState(icon: "hand.wave",
                                        title: "Сообщений пока нет",
                                        subtitle: "Напишите первым — это ни к чему не обязывает.")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                        }

                        ForEach(groupedMessages, id: \.key) { group in
                            DaySeparator(title: group.title)
                            ForEach(group.messages) { message in
                                MessageBubble(
                                    message: message,
                                    isMine: message.senderID == myID,
                                    onReply: { model.replyTo = message; inputFocused = true },
                                    onEdit: { model.beginEdit(message); inputFocused = true },
                                    onDelete: { pendingDelete = message },
                                    onReact: { reaction in
                                        Task { await model.react(message, reaction: reaction) }
                                    },
                                    onRetry: {
                                        Task { await model.retry(message, myID: myID) }
                                    },
                                    onDiscard: { model.discard(message) },
                                    onOpenProfile: {
                                        if let username = model.other?.username {
                                            navigate(.profile(username: username))
                                        }
                                    },
                                    onOpenAttachment: { urls, index in
                                        viewer = ImageViewerPayload(urls: urls, index: index)
                                    }
                                )
                            }
                        }

                        if model.isTypingRemote {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal, QSpacing.md)
                            .transition(.opacity)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchor)
                            .onAppear { isPinnedToBottom = true }
                            .onDisappear { isPinnedToBottom = false }
                    }
                    .padding(.vertical, QSpacing.md)
                    // A short conversation belongs at the bottom of the screen,
                    // not floating in the middle of an empty scroll view.
                    .frame(minHeight: geo.size.height, alignment: .bottom)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.count) { _ in
                    guard isPinnedToBottom || model.messages.last?.senderID == myID else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                    }
                }
                .onChange(of: model.isLoading) { loading in
                    guard !loading else { return }
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
                .onChange(of: inputFocused) { focused in
                    guard focused else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                    }
                }
            }
        }
    }

    private static let bottomAnchor = "qgram.chat.bottom"

    private struct MessageGroup: Identifiable {
        let key: String
        let title: String
        let messages: [QMessage]
        var id: String { key }
    }

    private var groupedMessages: [MessageGroup] {
        var groups: [MessageGroup] = []
        var currentKey: String?
        var buffer: [QMessage] = []

        for message in model.messages {
            let date = message.createdDate
            let key = QDate.dayKey(date)
            if key != currentKey {
                if let currentKey, !buffer.isEmpty {
                    groups.append(MessageGroup(key: currentKey,
                                               title: QDate.daySeparatorTitle(buffer.first?.createdDate),
                                               messages: buffer))
                }
                currentKey = key
                buffer = [message]
            } else {
                buffer.append(message)
            }
        }
        if let currentKey, !buffer.isEmpty {
            groups.append(MessageGroup(key: currentKey,
                                       title: QDate.daySeparatorTitle(buffer.first?.createdDate),
                                       messages: buffer))
        }
        return groups
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            if let reply = model.replyTo {
                contextBanner(icon: "arrowshape.turn.up.left.fill",
                              title: "Ответ @\(reply.username.isEmpty ? (model.other?.username ?? "") : reply.username)",
                              subtitle: reply.body) {
                    model.replyTo = nil
                }
            }
            if model.editing != nil {
                contextBanner(icon: "pencil",
                              title: "Редактирование",
                              subtitle: model.draft) {
                    model.cancelEdit()
                }
            }

            if !model.pendingAttachments.isEmpty || model.isUploading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: QSpacing.sm) {
                        ForEach(model.pendingAttachments) { attachment in
                            ZStack(alignment: .topTrailing) {
                                RemoteImage(url: attachment.trustedImageURL)
                                    .frame(width: 64, height: 64)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: QRadius.sm, style: .continuous))
                                Button {
                                    model.removeAttachment(attachment)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 18, height: 18)
                                        .background(Circle().fill(.black.opacity(0.6)))
                                }
                                .padding(3)
                            }
                        }
                        if model.isUploading {
                            RoundedRectangle(cornerRadius: QRadius.sm, style: .continuous)
                                .fill(QColor.card2)
                                .frame(width: 64, height: 64)
                                .overlay(ProgressView().controlSize(.small))
                        }
                    }
                    .padding(.horizontal, QSpacing.md)
                    .padding(.vertical, QSpacing.sm)
                }
            }

            HStack(alignment: .bottom, spacing: QSpacing.sm) {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 18))
                        .foregroundColor(QColor.muted)
                        .frame(width: 38, height: 38)
                }
                .disabled(model.isUploading || model.editing != nil)

                TextField("Сообщение", text: $model.draft, axis: .vertical)
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
                    .onChange(of: model.draft) { _ in
                        model.draftChanged()
                    }

                Button {
                    Task { await model.send(myID: myID) }
                } label: {
                    ZStack {
                        Circle()
                            .fill(model.canSend ? AnyShapeStyle(QColor.brandGradient) : AnyShapeStyle(QColor.card2))
                            .frame(width: 42, height: 42)
                        if model.isSending {
                            ProgressView().tint(.white).controlSize(.small)
                        } else {
                            Image(systemName: model.editing != nil ? "checkmark" : "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(model.canSend ? .white : QColor.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!model.canSend)
                .animation(.easeOut(duration: 0.15), value: model.canSend)
            }
            .padding(.horizontal, QSpacing.md)
            .padding(.vertical, QSpacing.sm)
        }
        .background(
            QColor.card
                .overlay(QColor.line.frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func contextBanner(icon: String, title: String, subtitle: String, onClose: @escaping () -> Void) -> some View {
        HStack(spacing: QSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(QColor.brandLight)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(QFont.caption(12))
                    .foregroundColor(QColor.brandLight)
                Text(subtitle)
                    .font(QFont.caption(12))
                    .foregroundColor(QColor.muted)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(QColor.muted)
            }
        }
        .padding(.horizontal, QSpacing.md)
        .padding(.vertical, 8)
        .background(QColor.card2)
    }
}

struct DaySeparator: View {
    let title: String

    var body: some View {
        Text(title)
            .font(QFont.caption(11))
            .foregroundColor(QColor.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(QColor.card2)
            .clipShape(Capsule())
            .padding(.vertical, QSpacing.sm)
    }
}
