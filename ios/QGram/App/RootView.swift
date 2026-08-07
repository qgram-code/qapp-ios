import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            QColor.bg.ignoresSafeArea()

            switch appState.phase {
            case .launching:
                LaunchView()
                    .transition(.opacity)
            case .signedOut:
                LoginView()
                    .transition(.opacity)
            case .signedIn:
                MainTabView()
                    .transition(.opacity)
            case .restricted(let message):
                RestrictedView(message: message)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.phase)
        .qToast($appState.toast)
        .task {
            await appState.bootstrap()
        }
    }
}

struct LaunchView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: QSpacing.lg) {
            QLogoMark(size: 76)
                .scaleEffect(pulse ? 1.04 : 0.96)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            ProgressView()
                .tint(QColor.brandLight)
        }
        .onAppear { pulse = true }
    }
}

/// The app mark: the site's paper plane on the brand gradient tile.
struct QLogoMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(QColor.brandGradient)
            Image(systemName: "paperplane.fill")
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundColor(.white)
                .rotationEffect(.degrees(-8))
                .offset(x: -size * 0.02, y: size * 0.01)
        }
        .frame(width: size, height: size)
        .shadow(color: QColor.brand.opacity(0.3), radius: size * 0.22, y: size * 0.07)
        .accessibilityLabel("QGram")
    }
}

struct RestrictedView: View {
    let message: String
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: QSpacing.lg) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44))
                .foregroundColor(QColor.danger)
            Text("Доступ ограничен")
                .font(QFont.title(22))
                .foregroundColor(QColor.textPrimary)
            Text(message)
                .font(QFont.body(15))
                .foregroundColor(QColor.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: QSpacing.sm) {
                Link(destination: AppConfig.websiteURL) {
                    Text("Открыть qgram.fun")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(QSecondaryButtonStyle(fullWidth: true))

                Button("Выйти из аккаунта") {
                    Task { await appState.leaveRestrictedScreen() }
                }
                .buttonStyle(QPrimaryButtonStyle())
            }
            .padding(.top, QSpacing.sm)
        }
        .padding(QSpacing.xl)
        .frame(maxWidth: 380)
    }
}
