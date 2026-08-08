import SwiftUI
import UIKit

/// Colour tokens mirrored 1:1 from the web design system (`static/style.css`,
/// "QGram Design System v2 — Dark-first"). Every token resolves per trait
/// collection so light mode is a real theme, not an inverted dark one.
enum QColor {
    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .light ? UIColor(hex: light) : UIColor(hex: dark)
        })
    }

    static let bg = dynamic(dark: 0x0F0F0F, light: 0xFAFAFA)
    static let card = dynamic(dark: 0x1A1A1A, light: 0xFFFFFF)
    static let card2 = dynamic(dark: 0x141414, light: 0xF5F5F5)
    static let cardHover = dynamic(dark: 0x222222, light: 0xF0F0F0)
    static let text = dynamic(dark: 0xE5E5E5, light: 0x171717)
    static let textPrimary = dynamic(dark: 0xFFFFFF, light: 0x0A0A0A)
    static let muted = dynamic(dark: 0x737373, light: 0x737373)
    static let brand = dynamic(dark: 0x9F5AFD, light: 0x8B5CF6)
    static let brandLight = dynamic(dark: 0xC084FC, light: 0xA855F7)
    static let danger = dynamic(dark: 0xEF4444, light: 0xDC2626)
    static let info = dynamic(dark: 0x38BDF8, light: 0x0284C7)
    static let ok = dynamic(dark: 0x22C55E, light: 0x16A34A)
    static let warn = dynamic(dark: 0xF59E0B, light: 0xD97706)
    static let chatMe = Color(UIColor(hex: 0x7C3AED))
    static let chatOther = dynamic(dark: 0x1F1F1F, light: 0xF0F0F0)
    static let chatOtherText = dynamic(dark: 0xE5E5E5, light: 0x171717)

    static var line: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .light
                ? UIColor.black.withAlphaComponent(0.08)
                : UIColor.white.withAlphaComponent(0.08)
        })
    }

    static var lineStrong: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .light
                ? UIColor.black.withAlphaComponent(0.14)
                : UIColor.white.withAlphaComponent(0.14)
        })
    }

    static var brandSubtle: Color {
        Color(UIColor { traits in
            let base = traits.userInterfaceStyle == .light ? UIColor(hex: 0xA855F7) : UIColor(hex: 0xC084FC)
            return base.withAlphaComponent(traits.userInterfaceStyle == .light ? 0.12 : 0.20)
        })
    }

    static var dangerSubtle: Color {
        Color(UIColor { traits in
            UIColor(hex: 0xEF4444).withAlphaComponent(traits.userInterfaceStyle == .light ? 0.08 : 0.12)
        })
    }

    static var okSubtle: Color {
        Color(UIColor { traits in
            UIColor(hex: 0x22C55E).withAlphaComponent(traits.userInterfaceStyle == .light ? 0.08 : 0.12)
        })
    }

    /// Brand gradient used for the primary CTA, the compose button and avatars
    /// without an image — the same purple ramp the site uses.
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brand, brandLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Corner radii from the web tokens (--radius / --radius-lg / --radius-xl).
enum QRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let full: CGFloat = 999
}

enum QSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum QFont {
    static func title(_ size: CGFloat = 22) -> Font { .system(size: size, weight: .bold, design: .default) }
    static func headline(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .semibold) }
    static func body(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .regular) }
    static func caption(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .medium) }
    static func mono(_ size: CGFloat = 14) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

extension Color {
    /// Parses `#RRGGBB` strings coming from the API (premium colour, room accent).
    init?(qgramHex: String?) {
        guard var raw = qgramHex?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else { return nil }
        self.init(UIColor(hex: value))
    }
}
