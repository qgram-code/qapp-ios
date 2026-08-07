import SwiftUI

@MainActor
final class RegisterViewModel: ObservableObject {
    @Published var username = ""
    @Published var email = ""
    @Published var password = ""
    @Published var code = ""
    @Published var agreedToRules = false
    @Published private(set) var challenge: QRegistrationChallenge?
    @Published private(set) var isBusy = false
    @Published private(set) var secondsLeft = 0
    @Published var error: String?
    @Published var info: String?

    private var timerTask: Task<Void, Never>?

    /// Mirrors USERNAME_RE on the server: 5–20 of [A-Za-z0-9_].
    var usernameIsValid: Bool {
        let value = username.trimmingCharacters(in: .whitespaces)
        guard (5...20).contains(value.count) else { return false }
        return value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    var emailIsValid: Bool {
        let value = email.trimmingCharacters(in: .whitespaces)
        guard let at = value.firstIndex(of: "@"), at != value.startIndex else { return false }
        let domain = value[value.index(after: at)...]
        return domain.contains(".") && !domain.hasSuffix(".") && !domain.hasPrefix(".")
    }

    var passwordIsValid: Bool { password.count >= 6 }

    var canSubmit: Bool {
        usernameIsValid && emailIsValid && passwordIsValid && agreedToRules && !isBusy
    }

    var canConfirm: Bool { code.count >= 4 && !isBusy }

    func start() async {
        guard canSubmit else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let challenge = try await APIClient.shared.register(
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                email: email.trimmingCharacters(in: .whitespaces).lowercased()
            )
            self.challenge = challenge
            startCountdown(from: challenge.expiresIn)
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось начать регистрацию"
        }
    }

    func resend() async {
        guard let challenge, !isBusy else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let refreshed = try await APIClient.shared.resendRegistrationCode(regToken: challenge.regToken)
            self.challenge = refreshed
            code = ""
            info = "Новый код отправлен"
            startCountdown(from: refreshed.expiresIn)
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось отправить код повторно"
        }
    }

    func confirm(appState: AppState) async {
        guard let challenge, canConfirm else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let response = try await APIClient.shared.completeRegistration(
                regToken: challenge.regToken,
                code: code.trimmingCharacters(in: .whitespaces)
            )
            timerTask?.cancel()
            password = ""
            await appState.signIn(user: response.user, token: response.token)
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось подтвердить код"
        }
    }

    func back() {
        timerTask?.cancel()
        challenge = nil
        code = ""
        error = nil
    }

    private func startCountdown(from seconds: Int) {
        timerTask?.cancel()
        secondsLeft = max(0, seconds)
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.secondsLeft <= 0 { return }
                self.secondsLeft -= 1
            }
        }
    }
}

struct RegisterView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = RegisterViewModel()
    @FocusState private var focused: Field?

    private enum Field {
        case username
        case email
        case password
        case code
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: QSpacing.lg) {
                    header

                    if model.challenge == nil {
                        form
                    } else {
                        confirmation
                    }

                    if let error = model.error {
                        QInlineError(message: error)
                    }
                }
                .padding(QSpacing.lg)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(LoginBackground().ignoresSafeArea())
            .navigationTitle(model.challenge == nil ? "Регистрация" : "Подтверждение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.challenge == nil ? "Отмена" : "Назад") {
                        if model.challenge == nil {
                            dismiss()
                        } else {
                            model.back()
                        }
                    }
                    .foregroundColor(QColor.muted)
                }
            }
        }
        .onChange(of: model.info) { message in
            guard let message else { return }
            appState.show(QToast(kind: .success, text: message))
            model.info = nil
        }
    }

    private var header: some View {
        VStack(spacing: QSpacing.sm) {
            QLogoMark(size: 60)
            Text(model.challenge == nil
                 ? "Создайте аккаунт в qgram"
                 : "Введите код из письма")
                .font(QFont.headline(17))
                .foregroundColor(QColor.textPrimary)
                .multilineTextAlignment(.center)
            if let challenge = model.challenge {
                Text("\(challenge.message) — \(model.email)")
                    .font(QFont.body(13))
                    .foregroundColor(QColor.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, QSpacing.md)
    }

    private var form: some View {
        VStack(spacing: QSpacing.md) {
            QTextField(title: "Имя пользователя", text: $model.username,
                       keyboard: .asciiCapable, contentType: .username,
                       submitLabel: .next, placeholder: "5–20 символов",
                       focus: $focused, field: Field.username) {
                focused = .email
            }
            requirement("Латиница, цифры и _, от 5 до 20 символов", ok: model.usernameIsValid, show: !model.username.isEmpty)

            QTextField(title: "Почта", text: $model.email,
                       keyboard: .emailAddress, contentType: .emailAddress,
                       submitLabel: .next, placeholder: "you@example.com",
                       focus: $focused, field: Field.email) {
                focused = .password
            }
            requirement("Нужна для подтверждения и входа", ok: model.emailIsValid, show: !model.email.isEmpty)

            QTextField(title: "Пароль", text: $model.password, isSecure: true,
                       contentType: .newPassword, submitLabel: .go,
                       placeholder: "минимум 6 символов",
                       focus: $focused, field: Field.password) {
                Task { await model.start() }
            }
            requirement("Минимум 6 символов", ok: model.passwordIsValid, show: !model.password.isEmpty)

            Toggle(isOn: $model.agreedToRules) {
                HStack(spacing: 4) {
                    Text("Согласен с")
                        .font(QFont.body(13))
                        .foregroundColor(QColor.muted)
                    Link("правилами", destination: AppConfig.websiteURL.appendingPathComponent("rules"))
                        .font(QFont.body(13))
                        .foregroundColor(QColor.brandLight)
                }
            }
            .tint(QColor.brand)

            Button {
                focused = nil
                Task { await model.start() }
            } label: {
                if model.isBusy {
                    ProgressView().tint(.white)
                } else {
                    Text("Получить код")
                }
            }
            .buttonStyle(QPrimaryButtonStyle(enabled: model.canSubmit))
            .disabled(!model.canSubmit)
        }
        .qCard()
    }

    private var confirmation: some View {
        VStack(spacing: QSpacing.md) {
            QTextField(title: "Код из письма", text: $model.code,
                       keyboard: .numberPad, contentType: .oneTimeCode,
                       submitLabel: .go, placeholder: "123456",
                       focus: $focused, field: Field.code) {
                Task { await model.confirm(appState: appState) }
            }
            .onChange(of: model.code) { newValue in
                let digits = newValue.filter(\.isNumber)
                if digits != newValue { model.code = digits }
                if digits.count > 8 { model.code = String(digits.prefix(8)) }
            }

            HStack {
                Image(systemName: "clock")
                Text(model.secondsLeft > 0
                     ? "Код действителен ещё \(model.secondsLeft / 60):\(String(format: "%02d", model.secondsLeft % 60))"
                     : "Срок действия кода истёк")
            }
            .font(QFont.caption(12))
            .foregroundColor(model.secondsLeft > 0 ? QColor.muted : QColor.danger)

            Button {
                Task { await model.confirm(appState: appState) }
            } label: {
                if model.isBusy {
                    ProgressView().tint(.white)
                } else {
                    Text("Создать аккаунт")
                }
            }
            .buttonStyle(QPrimaryButtonStyle(enabled: model.canConfirm))
            .disabled(!model.canConfirm)

            Button("Отправить код ещё раз") {
                Task { await model.resend() }
            }
            .buttonStyle(QSecondaryButtonStyle(fullWidth: true))
            .disabled(model.isBusy)
        }
        .qCard()
        .task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            focused = .code
        }
    }

    private func requirement(_ text: String, ok: Bool, show: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundColor(ok ? QColor.ok : QColor.muted)
            Text(text)
                .font(QFont.caption(11))
                .foregroundColor(ok ? QColor.ok : QColor.muted)
            Spacer()
        }
        .opacity(show ? 1 : 0.55)
    }
}
