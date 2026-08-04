import SwiftUI

struct RootTabView: View {
    @State private var selection: AppRoute = .practice

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppRoute.rootTabs) { route in
                NavigationStack {
                    RootPlaceholderView(route: route)
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

    var body: some View {
        Group {
            switch route {
            case .practice:
                PracticeView()
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
        case .history: "查看每次回答、润色和评分记录。"
        case .insights: "查看练习覆盖率和分数趋势。"
        case .settings: "配置 AI 模型、API Key 和隐私选项。"
        }
    }
}
