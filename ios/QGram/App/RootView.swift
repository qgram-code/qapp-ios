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

/// The app mark — the real qgram logo (`static/logo.png`), not an SF Symbol
/// stand-in, so the app and the site share one identity.
struct QLogoMark: View {
    var size: CGFloat = 64

    var body: some View {
        Image("QGramLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
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
