import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var push = PushManager.shared
    @AppStorage("qgram.appearance") private var appearanceRaw: String = QAppearance.dark.rawValue

    @State private var confirmLogout = false

    var body: some View {
        ScrollView {
            VStack(spacing: QSpacing.lg) {
                if let me = appState.me {
                    accountCard(me)
                }
                presenceCard
                pushCard
                appearanceCard
                linksCard
                aboutCard
            }
            .padding(QSpacing.md)
            .padding(.bottom, 40)
        }
        .background(QColor.bg.ignoresSafeArea())
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) {
                Task { await appState.signOut() }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func accountCard(_ me: QUser) -> some View {
        VStack(spacing: QSpacing.md) {
            HStack(spacing: QSpacing.md) {
                QAvatar(url: me.avatarURL, size: 52, ring: me.isPremium)
                VStack(alignment: .leading, spacing: 3) {
                    QUserLabel(displayName: me.displayName,
                               verified: me.verified,
                               isPremium: me.isPremium,
                               premiumEmoji: me.premiumEmoji,
                               premiumColor: me.premiumColor)
                    Text(me.handle)
                        .font(QFont.caption(12))
                        .foregroundColor(QColor.muted)
                }
                Spacer()
            }

            Button("Выйти из аккаунта") { confirmLogout = true }
                .buttonStyle(QSecondaryButtonStyle(fullWidth: true, tint: QColor.danger))
        }
        .qCard()
    }

    private var presenceCard: some View {
        VStack(alignment: .leading, spacing: QSpacing.md) {
            QSectionHeader(title: "Статус")
            ForEach([QPresence.online, .away, .doNotDisturb, .sleep], id: \.rawValue) { status in
                Button {
                    Task { await appState.updatePresence(status) }
                } label: {
                    HStack(spacing: QSpacing.md) {
                        QPresenceDot(presence: status, size: 12)
                        Text(status.title.capitalizedFirst)
                            .font(QFont.body(15))
                            .foregroundColor(QColor.text)
                        Spacer()
                        if appState.presenceStatus == status {
                            Image(systemName: "checkmark")
                                .foregroundColor(QColor.brand)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            Text("Статус обновляется, пока приложение открыто. При выходе из приложения вы становитесь офлайн.")
                .font(QFont.caption(11))
                .foregroundColor(QColor.muted)
        }
        .qCard()
    }

    private var pushCard: some View {
        VStack(alignment: .leading, spacing: QSpacing.md) {
            QSectionHeader(title: "Уведомления")
            HStack(spacing: QSpacing.md) {
                Image(systemName: pushIcon)
                    .foregroundColor(pushTint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pushTitle)
                        .font(QFont.body(15))
                        .foregroundColor(QColor.text)
                    Text(pushSubtitle)
                        .font(QFont.caption(11))
                        .foregroundColor(QColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if push.authorizationStatus == .notDetermined {
                Button("Включить уведомления") {
                    Task { await push.requestAuthorization() }
                }
                .buttonStyle(QSecondaryButtonStyle(fullWidth: true))
            } else if push.authorizationStatus == .denied {
                Button("Открыть настройки iOS") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(QSecondaryButtonStyle(fullWidth: true))
            }
        }
        .qCard()
        .task { await push.refreshStatus() }
    }

    private var pushIcon: String {
        switch push.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "bell.badge.fill"
        case .denied: return "bell.slash.fill"
        default: return "bell"
        }
    }

    private var pushTint: Color {
        switch push.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return QColor.ok
        case .denied: return QColor.danger
        default: return QColor.muted
        }
    }

    private var pushTitle: String {
        switch push.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "Push включены"
        case .denied: return "Push отключены"
        default: return "Push не настроены"
        }
    }

    private var pushSubtitle: String {
        switch push.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return push.deliveryEnabled
                ? "Устройство зарегистрировано на сервере."
                : "Устройство зарегистрировано; отправка пушей на сервере пока не настроена."
        case .denied:
            return "Разрешите уведомления в настройках iOS, чтобы получать их от qgram."
        default:
            return "Сообщения о лайках, комментариях и подписках."
        }
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: QSpacing.md) {
            QSectionHeader(title: "Оформление")
            Picker("Тема", selection: $appearanceRaw) {
                ForEach(QAppearance.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
        .qCard()
    }

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: QSpacing.sm) {
            QSectionHeader(title: "qgram.fun")
            linkRow(title: "Открыть сайт", icon: "safari", url: AppConfig.websiteURL)
            linkRow(title: "Правила", icon: "doc.text", url: AppConfig.websiteURL.appendingPathComponent("rules"))
            linkRow(title: "Уведомления", icon: "bell",
                    url: AppConfig.websiteURL.appendingPathComponent("notifications"))
            linkRow(title: "Настройки аккаунта", icon: "person.badge.key",
                    url: AppConfig.websiteURL.appendingPathComponent("settings"))
        }
        .qCard()
    }

    private func linkRow(title: String, icon: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: QSpacing.md) {
                Image(systemName: icon)
                    .frame(width: 22)
                    .foregroundColor(QColor.brandLight)
                Text(title)
                    .font(QFont.body(15))
                    .foregroundColor(QColor.text)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundColor(QColor.muted)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 7)
        }
    }

    private var aboutCard: some View {
        VStack(spacing: QSpacing.sm) {
            QLogoMark(size: 40)
            Text("QGram для iOS")
                .font(QFont.headline(15))
                .foregroundColor(QColor.textPrimary)
            Text("Версия \(AppConfig.appVersion)")
                .font(QFont.caption(12))
                .foregroundColor(QColor.muted)
        }
        .frame(maxWidth: .infinity)
        .qCard()
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
