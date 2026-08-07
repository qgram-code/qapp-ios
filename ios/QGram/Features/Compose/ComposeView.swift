import SwiftUI
import PhotosUI
import UIKit

struct ComposeView: View {
    var onPublished: (QPost) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isPrivate = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [UploadImage] = []
    @State private var isPreparing = false
    @State private var isPublishing = false
    @State private var error: String?
    @FocusState private var editorFocused: Bool

    private var maxImages: Int {
        (appState.me?.isPremium ?? false) ? AppConfig.postMaxImagesPremium : AppConfig.postMaxImagesFree
    }

    private var maxMB: Int {
        (appState.me?.isPremium ?? false) ? AppConfig.postMaxMBPremium : AppConfig.postMaxMBFree
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canPublish: Bool {
        (!trimmed.isEmpty || !images.isEmpty) && !isPublishing && !isPreparing
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.lg) {
                    editor

                    if !images.isEmpty {
                        selectedImages
                    }

                    if let error {
                        QInlineError(message: error)
                    }

                    options
                }
                .padding(QSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(QColor.bg.ignoresSafeArea())
            .navigationTitle("Новый пост")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundColor(QColor.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await publish() }
                    } label: {
                        if isPublishing {
                            ProgressView().tint(QColor.brand)
                        } else {
                            Text("Опубликовать").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canPublish)
                    .foregroundColor(canPublish ? QColor.brand : QColor.muted)
                }
            }
        }
        .onChange(of: pickerItems) { items in
            Task { await load(items: items) }
        }
        .task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            editorFocused = true
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Что нового?")
                        .font(QFont.body(16))
                        .foregroundColor(QColor.muted)
                        .padding(.top, 10)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(QFont.body(16))
                    .foregroundColor(QColor.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .focused($editorFocused)
            }
            .padding(8)
            .background(QColor.card)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous)
                    .strokeBorder(editorFocused ? QColor.brand.opacity(0.6) : QColor.line, lineWidth: 1)
            )

            HStack {
                Text("Первая строка станет заголовком поста")
                    .font(QFont.caption(11))
                    .foregroundColor(QColor.muted)
                Spacer()
                Text("\(text.count)")
                    .font(QFont.caption(11))
                    .foregroundColor(QColor.muted)
            }
        }
    }

    private var selectedImages: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: QSpacing.sm) {
                ForEach(images) { image in
                    ZStack(alignment: .topTrailing) {
                        if let uiImage = UIImage(data: image.data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 104, height: 104)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: QRadius.md, style: .continuous))
                        }
                        Button {
                            withAnimation { images.removeAll { $0.id == image.id } }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(.black.opacity(0.6)))
                        }
                        .padding(5)
                    }
                }
            }
        }
    }

    private var options: some View {
        VStack(spacing: QSpacing.md) {
            PhotosPicker(selection: $pickerItems,
                         maxSelectionCount: maxImages,
                         matching: .images,
                         photoLibrary: .shared()) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text(images.isEmpty ? "Добавить фото" : "Изменить выбор (\(images.count)/\(maxImages))")
                    Spacer()
                    if isPreparing {
                        ProgressView().controlSize(.small)
                    }
                }
                .font(QFont.headline(15))
                .foregroundColor(QColor.text)
                .padding(.vertical, 13)
                .padding(.horizontal, QSpacing.lg)
                .background(QColor.card)
                .clipShape(RoundedRectangle(cornerRadius: QRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: QRadius.md, style: .continuous)
                        .strokeBorder(QColor.line, lineWidth: 1)
                )
            }

            Toggle(isOn: $isPrivate) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Приватный пост")
                        .font(QFont.headline(15))
                        .foregroundColor(QColor.text)
                    Text("Виден только вам")
                        .font(QFont.caption(11))
                        .foregroundColor(QColor.muted)
                }
            }
            .tint(QColor.brand)
            .padding(.vertical, 10)
            .padding(.horizontal, QSpacing.lg)
            .background(QColor.card)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.md, style: .continuous)
                    .strokeBorder(QColor.line, lineWidth: 1)
            )
        }
    }

    // MARK: - Actions

    private func load(items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            images = []
            return
        }
        isPreparing = true
        error = nil
        var prepared: [UploadImage] = []
        var rejected = 0
        for item in items.prefix(maxImages) {
            if let image = await ImagePreparation.prepare(item, maxMB: maxMB) {
                prepared.append(image)
            } else {
                rejected += 1
            }
        }
        images = prepared
        isPreparing = false
        if rejected > 0 {
            error = "\(rejected) \(QDate.plural(rejected, "файл не подошёл", "файла не подошли", "файлов не подошли")) — слишком большой размер или неподдерживаемый формат."
        }
    }

    private func publish() async {
        guard canPublish else { return }
        isPublishing = true
        error = nil
        defer { isPublishing = false }
        do {
            let post = try await APIClient.shared.createPost(content: trimmed,
                                                             isPrivate: isPrivate,
                                                             images: images)
            onPublished(post)
            dismiss()
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось опубликовать пост."
        }
    }
}
