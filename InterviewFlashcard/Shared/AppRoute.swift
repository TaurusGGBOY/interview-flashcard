import Foundation

enum AppRoute: String, CaseIterable, Identifiable, Sendable {
    case practice
    case library
    case history
    case insights
    case settings

    static let rootTabs: [AppRoute] = [
        .practice,
        .library,
        .history,
        .insights,
        .settings,
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .practice: "练习"
        case .library: "题库"
        case .history: "历史"
        case .insights: "统计"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .practice: "rectangle.stack.fill"
        case .library: "books.vertical.fill"
        case .history: "clock.arrow.circlepath"
        case .insights: "chart.bar.xaxis"
        case .settings: "gearshape.fill"
        }
    }

    var accessibilityID: String {
        AccessibilityID.rootTab(self)
    }
}
