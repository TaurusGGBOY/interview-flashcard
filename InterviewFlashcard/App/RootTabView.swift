import SwiftUI

public struct RootTabView: View {
    nonisolated static let defaultSelection: AppRoute = .practice
    nonisolated static let globalEmptyDestination: AppRoute = .library

    @State private var selection: AppRoute

    public init() {
        _selection = State(initialValue: Self.defaultSelection)
    }

    public var body: some View {
        TabView(selection: $selection) {
            ForEach(AppRoute.rootTabs) { route in
                NavigationStack {
                    RootPlaceholderView(route: route) {
                        selection = Self.globalEmptyDestination
                    }
                }
                .tabItem {
                    Label(route.title, systemImage: route.systemImage)
                        .accessibilityIdentifier(route.accessibilityID)
                }
                .tag(route)
            }
        }
        .accessibilityIdentifier(AccessibilityID.appShell)
    }
}

private struct RootPlaceholderView: View {
    let route: AppRoute
    let onOpenLibrary: () -> Void

    var body: some View {
        Group {
            switch route {
            case .practice:
                PracticeView(onOpenLibrary: onOpenLibrary)
            case .library:
                LibraryView()
            case .history:
                HistoryView()
            case .insights:
                InsightsView()
            case .settings:
                SettingsView()
            default:
                ContentUnavailableView(
                    route.title,
                    systemImage: route.systemImage,
                    description: Text(description)
                )
                .navigationTitle(route.title)
                .accessibilityIdentifier(AccessibilityID.rootContent(route))
            }
        }
    }

    private var description: String {
        switch route {
        case .practice: "从题库中随机抽取一张题目开始练习。"
        case .library: "管理 Topic、题目和 Markdown 导入。"
        case .history: "查看每次回答和评分记录。"
        case .insights: "查看练习覆盖率和分数趋势。"
        case .settings: "配置 AI 模型、API Key 和隐私选项。"
        }
    }
}
