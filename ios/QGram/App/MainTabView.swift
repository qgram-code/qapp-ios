import SwiftUI

/// Every push destination in the app. Kept in one place so any stack can route
/// to any screen (a chat header can open a profile, a profile can open a chat).
enum QRoute: Hashable {
    case profile(username: String)
    case post(id: Int)
    case comments(postID: Int)
    case chat(convID: Int, title: String)
    case followers(username: String)
    case following(username: String)
    case notifications
    case settings
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    @State private var selection: Tab = .feed
    @State private var feedPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var chatsPath = NavigationPath()
    @State private var profilePath = NavigationPath()

    enum Tab: Hashable {
        case feed
        case search
        case chats
        case profile
    }

    var body: some View {
        TabView(selection: tabSelection) {
            NavigationStack(path: $feedPath) {
                FeedView()
                    .qRoutes()
            }
            .environment(\.qNavigate, QNavigateAction { feedPath.append($0) })
            .tabItem {
                Label("Лента", systemImage: selection == .feed ? "house.fill" : "house")
            }
            .badge(appState.unreadNotifications)
            .tag(Tab.feed)

            NavigationStack(path: $searchPath) {
                SearchView()
                    .qRoutes()
            }
            .environment(\.qNavigate, QNavigateAction { searchPath.append($0) })
            .tabItem {
                Label("Поиск", systemImage: "magnifyingglass")
            }
            .tag(Tab.search)

            NavigationStack(path: $chatsPath) {
                ChatsListView()
                    .qRoutes()
            }
            .environment(\.qNavigate, QNavigateAction { chatsPath.append($0) })
            .tabItem {
                Label("Чаты", systemImage: selection == .chats ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
            }
            .badge(appState.unreadChats)
            .tag(Tab.chats)

            NavigationStack(path: $profilePath) {
                MyProfileView()
                    .qRoutes()
            }
            .environment(\.qNavigate, QNavigateAction { profilePath.append($0) })
            .tabItem {
                Label("Профиль", systemImage: selection == .profile ? "person.fill" : "person")
            }
            .tag(Tab.profile)
        }
        .tint(QColor.brand)
    }

    /// Tapping the active tab pops its stack to the root — standard iOS behaviour
    /// that `TabView` does not provide for `NavigationStack`.
    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == selection {
                    switch newValue {
                    case .feed: feedPath = NavigationPath()
                    case .search: searchPath = NavigationPath()
                    case .chats: chatsPath = NavigationPath()
                    case .profile: profilePath = NavigationPath()
                    }
                }
                selection = newValue
            }
        )
    }
}

extension View {
    /// Installs the shared destination table on a navigation stack root.
    func qRoutes() -> some View {
        navigationDestination(for: QRoute.self) { route in
            switch route {
            case .profile(let username):
                ProfileView(username: username)
            case .post(let id):
                PostDetailView(postID: id)
            case .comments(let postID):
                CommentsView(postID: postID)
            case .chat(let convID, let title):
                ChatView(convID: convID, initialTitle: title)
            case .followers(let username):
                FollowListView(username: username, mode: .followers)
            case .following(let username):
                FollowListView(username: username, mode: .following)
            case .notifications:
                NotificationsView()
            case .settings:
                SettingsView()
            }
        }
    }
}
