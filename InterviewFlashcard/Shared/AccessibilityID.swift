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
    static let settingsAIService = "settings.ai-service"
    static let settingsAIServiceScreen = "settings.ai-service.screen"
    static let settingsAIProvider = "settings.ai-service.provider"
    static let settingsAIBaseURL = "settings.ai-service.base-url"
    static let settingsAITestConnection = "settings.ai-service.test"
    static let settingsAISave = "settings.ai-service.save"
    static let settingsAIMessage = "settings.ai-service.message"
    static let settingsPractice = "settings.practice"
    static let settingsPracticeScreen = "settings.practice.screen"
    static let settingsAIServiceRow = "settings.ai-service.row"
    static let settingsPracticeRow = "settings.practice.row"

    static func rootTab(_ route: AppRoute) -> String {
        "\(rootTabPrefix).\(route.rawValue)"
    }

    static func rootContent(_ route: AppRoute) -> String {
        "\(rootContentPrefix).\(route.rawValue)"
    }
}
