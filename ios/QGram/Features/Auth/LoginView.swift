import SwiftUI

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var username: String = TokenStore.lastUsername ?? ""
    @Published var password: String = ""
    @Published var isBusy = false
    @Published var error: String?
    @Published var challenge: TwoFactorChallenge?

    private let api = APIClient.shared

    var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isBusy
    }

    func submit(appState: AppState) async {
        guard canSubmit else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let outcome = try await api.login(
                username: username.trimmingCharacters(in: .whitespaces),
                password: password
            )
            switch outcome {
            case .success(let response):
                password = ""
                await appState.signIn(user: response.user, token: response.token)
            case .twoFactorRequired(let challenge):
                self.challenge = challenge
            }
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось войти. Попробуйте ещё раз."
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = LoginViewModel()
    @State private var showRegister = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case username
        case password
    }

    var body: some View {
        ScrollView {
            VStack(spacing: QSpacing.xl) {
                header

                VStack(spacing: QSpacing.md) {
                    QTextField(title: "Имя пользователя", text: $model.username,
                               keyboard: .asciiCapable, contentType: .username,
                               submitLabel: .next, focus: $focusedField, field: Field.username) {
                        focusedField = .password
                    }

                    QTextField(title: "Пароль", text: $model.password, isSecure: true,
                               contentType: .password, submitLabel: .go,
                               focus: $focusedField, field: Field.password) {
                        Task { await model.submit(appState: appState) }
                    }

                    if let error = model.error {
                        QInlineError(message: error)
                    }

                    Button {
                        focusedField = nil
                        Task { await model.submit(appState: appState) }
                    } label: {
                        if model.isBusy {
                            ProgressView().tint(.white)
                        } else {
                            Text("Войти")
                        }
                    }
                    .buttonStyle(QPrimaryButtonStyle(enabled: model.canSubmit))
                    .disabled(!model.canSubmit)
                    .padding(.top, QSpacing.xs)
                }
                .qCard(padding: QSpacing.lg)

                footer
            }
            .padding(.horizontal, QSpacing.lg)
            .padding(.vertical, QSpacing.xl)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LoginBackground().ignoresSafeArea())
        .sheet(isPresented: $showRegister) {
            RegisterView()
                .environmentObject(appState)
        }
        .sheet(item: challengeBinding) { wrapper in
            TwoFactorView(challenge: wrapper.challenge)
                .environmentObject(appState)
        }
    }

    private var header: some View {
        VStack(spacing: QSpacing.md) {
            QLogoMark(size: 72)
            VStack(spacing: 6) {
                Text("qgram")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(QColor.textPrimary)
                Text("Социальная сеть, где всё своё")
                    .font(QFont.body(15))
                    .foregroundColor(QColor.muted)
            }
        }
        .padding(.top, QSpacing.xl)
    }

    private var footer: some View {
        VStack(spacing: QSpacing.sm) {
            Text("Нет аккаунта?")
                .font(QFont.body(14))
                .foregroundColor(QColor.muted)
            Button("Создать аккаунт") {
                showRegister = true
            }
            .font(QFont.headline(15))
            .foregroundColor(QColor.brandLight)
            Text("Версия \(AppConfig.appVersion)")
                .font(QFont.caption(11))
                .foregroundColor(QColor.muted.opacity(0.7))
                .padding(.top, QSpacing.sm)
        }
    }

    /// `sheet(item:)` needs an `Identifiable` binding; the challenge itself is a
    /// plain value type coming from the API.
    private var challengeBinding: Binding<IdentifiableChallenge?> {
        Binding(
            get: { model.challenge.map(IdentifiableChallenge.init) },
            set: { newValue in model.challenge = newValue?.challenge }
        )
    }
}

struct IdentifiableChallenge: Identifiable {
    let challenge: TwoFactorChallenge
    var id: String { challenge.token }

    init(_ challenge: TwoFactorChallenge) {
        self.challenge = challenge
    }
}

/// Soft brand glow behind the login form — the app's only decorative background,
/// echoing the site's gradient theme.
struct LoginBackground: View {
    var body: some View {
        ZStack {
            QColor.bg
            RadialGradient(
                colors: [QColor.brand.opacity(0.28), .clear],
                center: .init(x: 0.15, y: 0.05),
                startRadius: 10,
                endRadius: 420
            )
            RadialGradient(
                colors: [QColor.brandLight.opacity(0.16), .clear],
                center: .init(x: 0.9, y: 0.85),
                startRadius: 10,
                endRadius: 380
            )
        }
    }
}
