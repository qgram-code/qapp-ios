import SwiftUI
import PhotosUI

struct EditProfileView: View {
    var onSaved: (QUser) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var bio: String = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var bannerItem: PhotosPickerItem?
    @State private var busy: BusyKind?
    @State private var error: String?
    @State private var user: QUser?
    @FocusState private var bioFocused: Bool

    private enum BusyKind: Equatable {
        case bio
        case avatar
        case banner
        case bannerDelete
    }

    private var bioRemaining: Int { AppConfig.bioMaxLength - bio.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.lg) {
                    images
                    bioEditor
                    if let error {
                        QInlineError(message: error)
                    }
                }
                .padding(QSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(QColor.bg.ignoresSafeArea())
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundColor(QColor.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveBio() }
                    } label: {
                        if busy == .bio {
                            ProgressView().tint(QColor.brand)
                        } else {
                            Text("Сохранить").fontWeight(.semibold)
                        }
                    }
                    .disabled(busy != nil || bioRemaining < 0)
                    .foregroundColor(busy == nil && bioRemaining >= 0 ? QColor.brand : QColor.muted)
                }
            }
        }
        .onAppear {
            user = appState.me
            bio = appState.me?.bio ?? ""
        }
        .onChange(of: avatarItem) { item in
            guard let item else { return }
            Task { await upload(avatar: item) }
        }
        .onChange(of: bannerItem) { item in
            guard let item else { return }
            Task { await upload(banner: item) }
        }
    }

    private var images: some View {
        VStack(spacing: QSpacing.md) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let url = user?.bannerURL {
                        RemoteImage(url: url)
                            .frame(height: 120)
                            .clipped()
                    } else {
                        QColor.brandGradient.frame(height: 120).opacity(0.7)
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous))

                QAvatar(url: user?.avatarURL, size: 78, ring: true)
                    .padding(.leading, QSpacing.lg)
                    .offset(y: 34)
            }
            .padding(.bottom, 38)

            HStack(spacing: QSpacing.sm) {
                PhotosPicker(selection: $avatarItem, matching: .images, photoLibrary: .shared()) {
                    pickerLabel(title: "Аватар",
                                icon: "person.crop.circle",
                                busy: busy == .avatar)
                }
                PhotosPicker(selection: $bannerItem, matching: .images, photoLibrary: .shared()) {
                    pickerLabel(title: "Баннер",
                                icon: "photo",
                                busy: busy == .banner)
                }
            }

            if user?.bannerPath.isEmpty == false {
                Button {
                    Task { await deleteBanner() }
                } label: {
                    HStack(spacing: 6) {
                        if busy == .bannerDelete {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "trash")
                        }
                        Text("Удалить баннер")
                    }
                }
                .buttonStyle(QSecondaryButtonStyle(fullWidth: true, tint: QColor.danger))
                .disabled(busy != nil)
            }

            Text("Аватар до \(AppConfig.avatarMaxMB) МБ, баннер до \(AppConfig.bannerMaxMB) МБ. Фото автоматически сжимается перед отправкой.")
                .font(QFont.caption(11))
                .foregroundColor(QColor.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pickerLabel(title: String, icon: String, busy: Bool) -> some View {
        HStack(spacing: 8) {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: icon)
            }
            Text(title)
        }
        .font(QFont.headline(15))
        .foregroundColor(QColor.text)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(QColor.card)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: QRadius.md, style: .continuous)
                .strokeBorder(QColor.line, lineWidth: 1)
        )
    }

    private var bioEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            QSectionHeader(title: "О себе", trailing: "\(max(0, bioRemaining))")
            ZStack(alignment: .topLeading) {
                if bio.isEmpty {
                    Text("Пара слов о себе")
                        .font(QFont.body(15))
                        .foregroundColor(QColor.muted)
                        .padding(.top, 10)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $bio)
                    .font(QFont.body(15))
                    .foregroundColor(QColor.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 130)
                    .focused($bioFocused)
                    .onChange(of: bio) { newValue in
                        if newValue.count > AppConfig.bioMaxLength {
                            bio = String(newValue.prefix(AppConfig.bioMaxLength))
                        }
                    }
            }
            .padding(8)
            .background(QColor.card)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous)
                    .strokeBorder(bioFocused ? QColor.brand.opacity(0.6) : QColor.line, lineWidth: 1)
            )
        }
    }

    // MARK: - Actions

    private func saveBio() async {
        guard busy == nil else { return }
        busy = .bio
        error = nil
        defer { busy = nil }
        do {
            let updated = try await APIClient.shared.updateBio(bio)
            apply(updated)
            appState.show(QToast(kind: .success, text: "Профиль обновлён"))
            dismiss()
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось сохранить профиль."
        }
    }

    private func upload(avatar item: PhotosPickerItem) async {
        busy = .avatar
        error = nil
        defer {
            busy = nil
            avatarItem = nil
        }
        guard let image = await ImagePreparation.prepare(item, maxDimension: 1024, maxMB: AppConfig.avatarMaxMB) else {
            error = "Не удалось подготовить изображение."
            return
        }
        do {
            let updated = try await APIClient.shared.uploadAvatar(imageData: image.data,
                                                                  filename: image.filename,
                                                                  mimeType: image.mimeType)
            apply(updated)
            appState.show(QToast(kind: .success, text: "Аватар обновлён"))
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось загрузить аватар."
        }
    }

    private func upload(banner item: PhotosPickerItem) async {
        busy = .banner
        error = nil
        defer {
            busy = nil
            bannerItem = nil
        }
        guard let image = await ImagePreparation.prepare(item, maxDimension: 2048, maxMB: AppConfig.bannerMaxMB) else {
            error = "Не удалось подготовить изображение."
            return
        }
        do {
            let updated = try await APIClient.shared.uploadBanner(imageData: image.data,
                                                                   filename: image.filename,
                                                                   mimeType: image.mimeType)
            apply(updated)
            appState.show(QToast(kind: .success, text: "Баннер обновлён"))
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось загрузить баннер."
        }
    }

    private func deleteBanner() async {
        busy = .bannerDelete
        error = nil
        defer { busy = nil }
        do {
            let updated = try await APIClient.shared.deleteBanner()
            apply(updated)
            appState.show(QToast(kind: .success, text: "Баннер удалён"))
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось удалить баннер."
        }
    }

    private func apply(_ updated: QUser) {
        user = updated
        bio = updated.bio
        appState.updateMe(updated)
        onSaved(updated)
    }
}
