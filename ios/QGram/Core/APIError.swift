import Foundation

/// Every failure the app can show the user, with a Russian message ready for UI.
enum APIError: Error, LocalizedError, Equatable {
    /// The server answered with `{"ok": false, "error": "...", "message": "..."}`.
    case api(code: String, message: String, status: Int)
    /// 401 — the stored token is gone or was rotated away.
    case unauthorized
    /// Network stack failure (offline, DNS, TLS, timeout).
    case network(String)
    /// The response was not JSON we could understand.
    case decoding(String)
    /// 429 with a `Retry-After` hint.
    case rateLimited(retryAfter: Int?)

    var code: String {
        switch self {
        case .api(let code, _, _): return code
        case .unauthorized: return "auth_required"
        case .network: return "network"
        case .decoding: return "decoding"
        case .rateLimited: return "rate_limited"
        }
    }

    var errorDescription: String? { userMessage }

    var userMessage: String {
        switch self {
        case .unauthorized:
            return "Сессия истекла. Войдите заново."
        case .network(let details):
            return details.isEmpty ? "Нет соединения с qgram.fun" : details
        case .decoding:
            return "Сервер вернул неожиданный ответ. Попробуйте позже."
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > 0 {
                return "Слишком много запросов. Повторите через \(retryAfter) \(QDate.plural(retryAfter, "секунду", "секунды", "секунд"))."
            }
            return "Слишком много запросов. Попробуйте чуть позже."
        case .api(let code, let message, _):
            return APIError.localized(code: code, fallback: message)
        }
    }

    /// True when the account itself is restricted — the UI shows a dedicated
    /// blocking screen instead of an inline error.
    var isAccountRestriction: Bool {
        ["banned", "frozen", "sumsub_blocked", "account_deleted"].contains(code)
    }

    static func localized(code: String, fallback: String) -> String {
        switch code {
        case "auth_required": return "Требуется вход в аккаунт."
        case "invalid_credentials": return "Неверный логин или пароль."
        case "invalid_challenge": return "Сессия подтверждения истекла. Войдите заново."
        case "challenge_expired": return "Время на ввод кода истекло. Войдите заново."
        case "invalid_code": return "Неверный код подтверждения."
        case "code_expired": return "Код истёк. Запросите новый."
        case "code_not_found": return "Код не найден. Запросите новый."
        case "rate_limited": return "Слишком много попыток. Подождите немного."
        case "forbidden": return "Недостаточно прав."
        case "not_found": return "Не найдено."
        case "bad_request": return "Некорректный запрос."
        case "empty_post": return "Пост не может быть пустым."
        case "too_many_images": return "Слишком много изображений."
        case "invalid_file_type": return "Неподдерживаемый формат файла."
        case "file_too_large": return "Файл слишком большой."
        case "banned": return "Аккаунт заблокирован."
        case "frozen": return "Аккаунт заморожен."
        case "frozen_sender": return "Аккаунт заморожен — отправка недоступна."
        case "sumsub_blocked": return "Аккаунт ограничен до прохождения проверки."
        case "account_deleted": return "Аккаунт удалён."
        case "email_required": return "К аккаунту не привязана почта — 2FA невозможна."
        case "blocked": return "Пользователь недоступен."
        case "dm_closed": return "Пользователь не принимает личные сообщения."
        case "premium_required": return "Доступно только с премиумом."
        case "csrf": return "Не удалось подтвердить запрос. Повторите вход."
        case "app_required": return "Действие доступно только в приложении."
        default:
            return fallback.isEmpty ? "Что-то пошло не так. Попробуйте ещё раз." : fallback
        }
    }
}

/// Raised by `/api/login` when the account has 2FA enabled.
struct TwoFactorChallenge: Equatable {
    let token: String
    let expiresIn: Int
    let message: String
}
