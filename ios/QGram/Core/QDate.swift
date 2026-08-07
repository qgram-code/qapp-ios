import Foundation

/// The backend stores naive UTC timestamps (`datetime.utcnow().isoformat()`),
/// i.e. `2026-08-07T21:53:00` with **no** timezone marker. Parsing those with a
/// local-time formatter silently shifts every timestamp by the device offset,
/// so every conversion goes through here.
enum QDate {
    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private static let utcFractionalFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayAndTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d MMMM HH:mm")
        return formatter
    }()

    private static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return formatter
    }()

    private static let daySeparator: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return formatter
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if let date = utcFormatter.date(from: value) { return date }
        if let date = utcFractionalFormatter.date(from: value) { return date }
        if let date = isoFormatter.date(from: value) { return date }
        // Last resort: a bare date such as `2026-08-07`.
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone(identifier: "UTC")
        fallback.dateFormat = "yyyy-MM-dd"
        return fallback.date(from: value)
    }

    static func nowUTCString() -> String {
        utcFormatter.string(from: Date())
    }

    /// Short relative label used on post cards and chat rows.
    static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 0 { return timeOnly.string(from: date) }
        if seconds < 60 { return "только что" }
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes) \(plural(minutes, "минуту", "минуты", "минут")) назад"
        }
        if Calendar.current.isDateInToday(date) {
            return timeOnly.string(from: date)
        }
        if Calendar.current.isDateInYesterday(date) {
            return "вчера, " + timeOnly.string(from: date)
        }
        if let days = Calendar.current.dateComponents([.day], from: date, to: now).day, days < 7 {
            return dayAndTime.string(from: date)
        }
        if Calendar.current.isDate(date, equalTo: now, toGranularity: .year) {
            return dayAndTime.string(from: date)
        }
        return fullDate.string(from: date)
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "" }
        return timeOnly.string(from: date)
    }

    static func daySeparatorTitle(_ date: Date?) -> String {
        guard let date else { return "" }
        if Calendar.current.isDateInToday(date) { return "Сегодня" }
        if Calendar.current.isDateInYesterday(date) { return "Вчера" }
        return daySeparator.string(from: date)
    }

    static func dayKey(_ date: Date?) -> String {
        guard let date else { return "" }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod100 = abs(count) % 100
        let mod10 = abs(count) % 10
        if mod100 >= 11 && mod100 <= 14 { return many }
        if mod10 == 1 { return one }
        if mod10 >= 2 && mod10 <= 4 { return few }
        return many
    }
}
