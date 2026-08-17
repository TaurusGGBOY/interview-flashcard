import SwiftUI

public struct RootTabView: View {
    nonisolated static let defaultSelection: AppRoute = .practice
    nonisolated static let globalEmptyDestination: AppRoute = .library

    @State private var selection: AppRoute
    @State private var practiceLaunchRequest: PracticeLaunchRequest?

    public init() {
        _selection = State(initialValue: Self.defaultSelection)
    }

    public var body: some View {
        TabView(selection: $selection) {
            ForEach(AppRoute.rootTabs) { route in
                NavigationStack {
                    RootPlaceholderView(
                        route: route,
                        launchRequest: practiceLaunchRequest,
                        onLaunchRequestConsumed: { practiceLaunchRequest = nil },
                        onOpenLibrary: {
                            selection = Self.globalEmptyDestination
                        },
                        onOpenQuestion: { questionID in
                            practiceLaunchRequest = PracticeLaunchRequest(
                                questionID: questionID,
                                startInAnswer: true
                            )
                            selection = .practice
                        }
                    )
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
    let launchRequest: PracticeLaunchRequest?
    let onLaunchRequestConsumed: () -> Void
    let onOpenLibrary: () -> Void
    let onOpenQuestion: (UUID) -> Void

    var body: some View {
        Group {
            switch route {
            case .practice:
                PracticeView(
                    launchRequest: launchRequest,
                    onLaunchRequestConsumed: onLaunchRequestConsumed,
                    onOpenLibrary: onOpenLibrary
                )
            case .library:
                LibraryView(onOpenQuestion: onOpenQuestion)
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
        case .library: "管理 Topic、题目和文本文件导入。"
        case .history: "查看每次回答和评分记录。"
        case .insights: "查看练习覆盖率和分数趋势。"
        case .settings: "配置 AI 模型、API Key 和隐私选项。"
        }
    }
}
