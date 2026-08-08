import SwiftUI
import UIKit

// MARK: - Surfaces

struct QCardModifier: ViewModifier {
    var padding: CGFloat = QSpacing.lg
    var radius: CGFloat = QRadius.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(QColor.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(QColor.line, lineWidth: 1)
            )
    }
}

extension View {
    func qCard(padding: CGFloat = QSpacing.lg, radius: CGFloat = QRadius.lg) -> some View {
        modifier(QCardModifier(padding: padding, radius: radius))
    }

    /// Hides a view without changing layout — used for skeleton states.
    @ViewBuilder
    func qHidden(_ hidden: Bool) -> some View {
        if hidden { self.hidden() } else { self }
    }
}

// MARK: - Buttons

struct QPrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QFont.headline())
            .foregroundColor(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, QSpacing.xl)
            .frame(maxWidth: fullWidth ? CGFloat.infinity : nil)
            .background {
                if enabled {
                    QColor.brandGradient
                } else {
                    QColor.card2
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: QRadius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct QSecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = false
    var tint: Color = QColor.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QFont.headline(15))
            .foregroundColor(tint)
            .padding(.vertical, 11)
            .padding(.horizontal, QSpacing.lg)
            .frame(maxWidth: fullWidth ? CGFloat.infinity : nil)
            .background(QColor.card2)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.md, style: .continuous)
                    .strokeBorder(QColor.line, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Type eraser so a view can pick between two button styles at runtime.
struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { configuration in AnyView(style.makeBody(configuration: configuration)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}

struct QIconButtonStyle: ButtonStyle {
    var size: CGFloat = 38

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(QColor.card2)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(QColor.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Text field

/// Labelled input with the brand focus ring.
///
/// Focus is owned by the *parent* (`FocusState` cannot be forwarded into a child
/// view any other way), which is what makes "next field" chaining work.
struct QTextField<Field: Hashable>: View {
    let title: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .never
    var submitLabel: SubmitLabel = .next
    var placeholder: String = ""
    var focus: FocusState<Field?>.Binding
    let field: Field
    var onSubmit: (() -> Void)?

    private var isFocused: Bool { focus.wrappedValue == field }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty {
                Text(title)
                    .font(QFont.caption())
                    .foregroundColor(QColor.muted)
            }
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(QFont.body(16))
            .foregroundColor(QColor.textPrimary)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled(true)
            .submitLabel(submitLabel)
            .focused(focus, equals: field)
            .onSubmit { onSubmit?() }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(QColor.card2)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.md, style: .continuous)
                    .strokeBorder(isFocused ? QColor.brand : QColor.line, lineWidth: isFocused ? 1.5 : 1)
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

// MARK: - Identity

struct QAvatar: View {
    let url: URL?
    var size: CGFloat = 44
    var ring: Bool = false

    var body: some View {
        RemoteImage(url: url) {
            AnyView(
                ZStack {
                    QColor.card2
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.42))
                        .foregroundColor(QColor.muted)
                }
            )
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(ring ? QColor.brand : QColor.line, lineWidth: ring ? 2 : 1)
        )
    }
}

struct QVerifiedBadge: View {
    var size: CGFloat = 14

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(QColor.brandLight)
            .accessibilityLabel("Верифицирован")
    }
}

/// Username + verification + premium emoji, laid out consistently everywhere.
struct QUserLabel: View {
    let displayName: String
    var verified: Bool = false
    var isPremium: Bool = false
    var premiumEmoji: String = ""
    var premiumColor: String = ""
    var font: Font = QFont.headline()

    var body: some View {
        HStack(spacing: 4) {
            Text(displayName)
                .font(font)
                .foregroundColor(Color(qgramHex: premiumColor) ?? QColor.textPrimary)
                .lineLimit(1)
            if verified { QVerifiedBadge() }
            if isPremium, !premiumEmoji.isEmpty {
                Text(premiumEmoji).font(.system(size: 13))
            } else if isPremium {
                Image(systemName: "star.fill")
                    .font(.system(size: 11))
                    .foregroundColor(QColor.warn)
                    .accessibilityLabel("Премиум")
            }
        }
    }
}

struct QPresenceDot: View {
    let presence: QPresence
    var size: CGFloat = 10

    private var color: Color {
        switch presence {
        case .online: return QColor.ok
        case .away, .sleep: return QColor.warn
        case .doNotDisturb: return QColor.danger
        case .offline: return QColor.muted
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(QColor.bg, lineWidth: 2))
            .accessibilityLabel(presence.title)
    }
}

// MARK: - Feedback

struct QBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(QColor.brand))
                .accessibilityLabel("\(count) новых")
        }
    }
}

struct QEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String = ""
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: QSpacing.md) {
            ZStack {
                Circle()
                    .fill(QColor.brandSubtle)
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(QColor.brandLight)
            }
            Text(title)
                .font(QFont.headline(17))
                .foregroundColor(QColor.textPrimary)
                .multilineTextAlignment(.center)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(QFont.body(14))
                    .foregroundColor(QColor.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(QSecondaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: 320)
        .padding(QSpacing.xl)
    }
}

struct QErrorView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: QSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundColor(QColor.warn)
            Text(message)
                .font(QFont.body(14))
                .foregroundColor(QColor.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button("Повторить", action: retry)
                    .buttonStyle(QSecondaryButtonStyle())
            }
        }
        .padding(QSpacing.xl)
        .frame(maxWidth: 340)
    }
}

/// Inline, dismissible error strip used inside forms.
struct QInlineError: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(QColor.danger)
            Text(message)
                .font(QFont.body(13))
                .foregroundColor(QColor.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(QColor.dangerSubtle)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.md, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct QToast: Equatable, Identifiable {
    enum Kind: Equatable {
        case success
        case error
        case info
    }

    let id = UUID()
    let kind: Kind
    let text: String

    static func == (lhs: QToast, rhs: QToast) -> Bool { lhs.id == rhs.id }
}

struct QToastView: View {
    let toast: QToast

    private var icon: String {
        switch toast.kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch toast.kind {
        case .success: return QColor.ok
        case .error: return QColor.danger
        case .info: return QColor.info
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(tint)
            Text(toast.text)
                .font(QFont.body(14))
                .foregroundColor(QColor.textPrimary)
                .lineLimit(3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(QColor.card)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: QRadius.md, style: .continuous)
                .strokeBorder(QColor.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .padding(.horizontal, QSpacing.lg)
    }
}

struct QToastHost: ViewModifier {
    @Binding var toast: QToast?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    QToastView(toast: toast)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .id(toast.id)
                        .zIndex(10)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast?.id)
            .task(id: toast?.id) {
                guard toast != nil else { return }
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                guard !Task.isCancelled else { return }
                toast = nil
            }
    }
}

extension View {
    func qToast(_ toast: Binding<QToast?>) -> some View {
        modifier(QToastHost(toast: toast))
    }
}

// MARK: - Misc

struct QSkeletonRow: View {
    var height: CGFloat = 96

    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous)
            .fill(QColor.card)
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.lg, style: .continuous)
                    .strokeBorder(QColor.line, lineWidth: 1)
            )
            .opacity(shimmer ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: shimmer)
            .onAppear { shimmer = true }
    }
}

struct QSectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
                .font(QFont.caption(12))
                .foregroundColor(QColor.muted)
                .textCase(.uppercase)
                .tracking(0.6)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(QFont.caption(12))
                    .foregroundColor(QColor.muted)
            }
        }
    }
}
