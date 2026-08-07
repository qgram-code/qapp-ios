import SwiftUI

/// Push action injected by each tab's `NavigationStack`, so leaf views can
/// navigate without owning (or knowing about) the path they live in.
struct QNavigateAction {
    let handler: (QRoute) -> Void

    func callAsFunction(_ route: QRoute) {
        handler(route)
    }
}

private struct QNavigateKey: EnvironmentKey {
    static let defaultValue = QNavigateAction { _ in }
}

extension EnvironmentValues {
    var qNavigate: QNavigateAction {
        get { self[QNavigateKey.self] }
        set { self[QNavigateKey.self] = newValue }
    }
}
