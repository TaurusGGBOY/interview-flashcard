import Foundation

enum AccessibilityID {
    static let rootTabPrefix = "root.tab"
    static let rootContentPrefix = "root.content"
    static let appShell = "app.shell"
    static let settingsScreen = "settings.screen"
    static let settingsAPIKey = "settings.api-key"
    static let settingsModel = "settings.model"
    static let settingsSaveKey = "settings.save-key"
    static let settingsClearKey = "settings.clear-key"
    static let settingsMessage = "settings.message"

    static func rootTab(_ route: AppRoute) -> String {
        "\(rootTabPrefix).\(route.rawValue)"
    }

    static func rootContent(_ route: AppRoute) -> String {
        "\(rootContentPrefix).\(route.rawValue)"
    }
}
