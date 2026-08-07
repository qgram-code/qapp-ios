import SwiftUI

struct TwoFactorView: View {
    let challenge: TwoFactorChallenge

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var code: String = ""
    @State private var isBusy = false
    @State private var error: String?
    @State private var secondsLeft: Int
    @FocusState private var focused: Field?

    private enum Field {
        case code
    }

    init(challenge: TwoFactorChallenge) {
        self.challenge = challenge
        _secondsLeft = State(initialValue: max(0, challenge.expiresIn))
    }

    private var canSubmit: Bool {
        code.count >= 4 && !isBusy && secondsLeft > 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: QSpacing.xl) {
                VStack(spacing: QSpacing.md) {
                    ZStack {
                        Circle().fill(QColor.brandSubtle).frame(width: 76, height: 76)
                        Image(systemName: "envelope.badge.shield.half.filled")
                            .font(.system(size: 30))
                            .foregroundColor(QColor.brandLight)
                    }
                    Text("Подтверждение входа")
                        .font(QFont.title(21))
                        .foregroundColor(QColor.textPrimary)
                    Text(challenge.message)
                        .font(QFont.body(14))
                        .foregroundColor(QColor.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, QSpacing.xl)

                VStack(spacing: QSpacing.md) {
                    QTextField(title: "Код из письма", text: $code,
                               keyboard: .numberPad, contentType: .oneTimeCode,
                               submitLabel: .go, placeholder: "123456",
                               focus: $focused, field: Field.code) {
                        Task { await submit() }
                    }
                    .onChange(of: code) { newValue in
                        let digits = newValue.filter(\.isNumber)
                        if digits != newValue { code = digits }
                        if digits.count > 8 { code = String(digits.prefix(8)) }
                    }

                    if let error {
                        QInlineError(message: error)
                    }

                    HStack {
                        Image(systemName: "clock")
                        Text(secondsLeft > 0
                             ? "Код действителен ещё \(secondsLeft / 60):\(String(format: "%02d", secondsLeft % 60))"
                             : "Срок действия кода истёк")
                    }
                    .font(QFont.caption(12))
                    .foregroundColor(secondsLeft > 0 ? QColor.muted : QColor.danger)

                    Button {
                        Task { await submit() }
                    } label: {
                        if isBusy {
                            ProgressView().tint(.white)
                        } else {
                            Text("Подтвердить")
                        }
                    }
                    .buttonStyle(QPrimaryButtonStyle(enabled: canSubmit))
                    .disabled(!canSubmit)
                }
                .qCard()

                Spacer(minLength: 0)
            }
            .padding(QSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(QColor.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundColor(QColor.muted)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .task {
            focused = .code
            while secondsLeft > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                secondsLeft -= 1
            }
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let response = try await APIClient.shared.completeTwoFactor(
                challengeToken: challenge.token,
                code: code.trimmingCharacters(in: .whitespaces)
            )
            await appState.signIn(user: response.user, token: response.token)
            dismiss()
        } catch let error as APIError {
            self.error = error.userMessage
        } catch {
            self.error = "Не удалось подтвердить код."
        }
    }
}
