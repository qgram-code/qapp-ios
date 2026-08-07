import SwiftUI
import UIKit

/// Theme preference, mirroring the site's light/dark switch.
enum QAppearance: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Как в системе"
        case .dark: return "Тёмная"
        case .light: return "Светлая"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

@main
struct QGramApp: App {
    @UIApplicationDelegateAdaptor(QGramAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("qgram.appearance") private var appearanceRaw: String = QAppearance.dark.rawValue

    init() {
        QGramAppearance.apply()
    }

    private var appearance: QAppearance {
        QAppearance(rawValue: appearanceRaw) ?? .dark
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(appearance.colorScheme)
                .tint(QColor.brand)
        }
        .onChange(of: scenePhase) { newPhase in
            appState.handleScenePhase(newPhase)
        }
    }
}

/// UIKit-level chrome SwiftUI does not fully cover (nav bar / tab bar material).
enum QGramAppearance {
    static func apply() {
        let surface = UIColor { traits in
            traits.userInterfaceStyle == .light
                ? UIColor(hex: 0xFAFAFA).withAlphaComponent(0.92)
                : UIColor(hex: 0x0F0F0F).withAlphaComponent(0.9)
        }
        let hairline = UIColor { traits in
            traits.userInterfaceStyle == .light
                ? UIColor.black.withAlphaComponent(0.08)
                : UIColor.white.withAlphaComponent(0.08)
        }
        let label = UIColor { traits in
            traits.userInterfaceStyle == .light ? UIColor(hex: 0x0A0A0A) : UIColor.white
        }

        let navigation = UINavigationBarAppearance()
        navigation.configureWithDefaultBackground()
        navigation.backgroundColor = surface
        navigation.shadowColor = hairline
        navigation.titleTextAttributes = [.foregroundColor: label]
        navigation.largeTitleTextAttributes = [.foregroundColor: label]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundColor = surface
        tab.shadowColor = hairline
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}
