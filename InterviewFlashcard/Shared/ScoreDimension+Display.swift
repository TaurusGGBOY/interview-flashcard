extension ScoreDimension {
    var displayName: String {
        switch self {
        case .correctness: "正确性"
        case .coverage: "覆盖度"
        case .reasoning: "推理深度"
        case .structure: "结构清晰"
        case .tradeoffs: "应用与取舍"
        case .precision: "准确简洁"
        }
    }
}
