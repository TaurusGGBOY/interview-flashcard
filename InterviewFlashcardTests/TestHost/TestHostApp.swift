import SwiftUI

@main
struct InterviewFlashcardTestHost: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                TestHostEvaluationScenario(
                    title: "混合评分",
                    totalScore: 68,
                    dimensions: [
                        .init(name: "正确性", score: 82, feedback: "核心结论基本正确。", evidence: "使用幂等键避免重复创建", missedPoint: "没有说明幂等键的生命周期"),
                        .init(name: "覆盖度", score: 60, feedback: "覆盖了主流程，但遗漏故障恢复。", evidence: "说明了重试和超时", missedPoint: "缺少数据恢复与补偿策略"),
                        .init(name: "推理深度", score: 45, feedback: "有结论，机制和边界仍需展开。", evidence: "选择最终一致性", missedPoint: "没有解释选择背后的不变量"),
                        .init(name: "结构清晰", score: 74, feedback: "分段清楚，少量跳跃。", evidence: "先讲事务再讲消息", missedPoint: "没有用故障场景串联方案"),
                        .init(name: "应用与取舍", score: 50, feedback: "提到可用性与吞吐量，但权衡不完整。", evidence: "关注吞吐量", missedPoint: "缺少成本和复杂度的取舍"),
                        .init(name: "准确简洁", score: 88, feedback: "术语准确，表达较紧凑。", evidence: "使用重复消费一词", missedPoint: nil)
                    ],
                    referenceAnswer: "高级回答应先给出业务不变量与一致性边界，再解释幂等键、事务消息、重试退避和去重表如何协作。需要明确超时、重复消费、部分失败和数据恢复的处理，以及可观测性指标和工程成本之间的取舍。",
                    showDetails: true
                )
                .tabItem { Label("混合分", systemImage: "hexagon") }

                TestHostEvaluationScenario(
                    title: "零分（不可评分）",
                    totalScore: 0,
                    dimensions: TestHostDimension.zero,
                    referenceAnswer: "请先提交包含技术机制、边界场景和工程权衡的完整回答。",
                    showDetails: true
                )
                .tabItem { Label("零分", systemImage: "slash.circle") }

                TestHostEvaluationScenario(
                    title: "满分答案与大字",
                    totalScore: 100,
                    dimensions: TestHostDimension.full,
                    referenceAnswer: "先定义不变量：同一业务请求最多成功一次、库存不能为负、已确认订单最终可追溯。入口使用幂等键和唯一约束，订单与库存写入在本地事务内完成，跨服务通知通过事务消息或 outbox 投递。消费者使用业务键去重并让处理逻辑幂等；重试采用指数退避和上限，超时转入可重放的补偿队列。\n\n对高并发场景使用分片、限流和背压，监控延迟、重复率、积压和补偿成功率；对不可恢复错误保留人工介入路径。最终一致性换取可用性和吞吐量，但增加了状态机、对账和运维复杂度，需用故障演练与数据校验验证不变量。",
                    showDetails: true
                )
                .dynamicTypeSize(.accessibility5)
                .tabItem { Label("满分", systemImage: "star.fill") }

                TestHostQuestionCardScenario(
                    title: "短题居中",
                    question: "什么是幂等性？",
                    identifier: "test-host.short-question"
                )
                .tabItem { Label("短题", systemImage: "text.aligncenter") }

                TestHostQuestionCardScenario(
                    title: "长题滚动",
                    question: "请设计一个支持水平扩展的订单服务。说明请求幂等、库存扣减、消息投递、数据库事务、重试与超时、重复消费、部分失败、可观测性和数据恢复之间的关系，并解释在一致性、可用性、吞吐量和实现复杂度之间如何做工程取舍。\n\n请同时说明如何验证方案在高并发和依赖服务故障时仍然满足业务不变量。",
                    identifier: "test-host.long-question"
                )
                .tabItem { Label("长题", systemImage: "scroll") }

                TestHostQuestionCardScenario(
                    title: "最大字体",
                    question: "解释缓存失效策略，并说明一个失败场景。",
                    identifier: "test-host.maximum-dynamic-type"
                )
                .dynamicTypeSize(.accessibility5)
                .tabItem { Label("大字", systemImage: "textformat.size.larger") }
            }
            .tint(.indigo)
        }
    }
}

private struct TestHostQuestionCardScenario: View {
    let title: String
    let question: String
    let identifier: String

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ZStack {
                LinearGradient(
                    colors: [.indigo, .teal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                ScrollView(.vertical) {
                    Text(question)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 320, alignment: .center)
                        .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(.white.opacity(0.5), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier(identifier)

            HStack(spacing: 12) {
                Label("跳过", systemImage: "xmark")
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(.red, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Label("开始回答", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(.green, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .font(.body.weight(.semibold))
        }
        .padding(18)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}

private struct TestHostDimension: Identifiable {
    let id = UUID()
    let name: String
    let score: Int
    let feedback: String
    let evidence: String
    let missedPoint: String?

    init(name: String, score: Int, feedback: String, evidence: String, missedPoint: String? = nil) {
        self.name = name
        self.score = score
        self.feedback = feedback
        self.evidence = evidence
        self.missedPoint = missedPoint
    }

    static let zero = [
        TestHostDimension(name: "正确性", score: 0, feedback: "没有可验证的技术内容。", evidence: "（无可引用内容）", missedPoint: "需要给出可核验的机制"),
        TestHostDimension(name: "覆盖度", score: 0, feedback: "没有覆盖题目关键点。", evidence: "（无可引用内容）", missedPoint: "需要回应题干中的关键场景"),
        TestHostDimension(name: "推理深度", score: 0, feedback: "没有形成推理链。", evidence: "（无可引用内容）", missedPoint: "需要解释因果关系"),
        TestHostDimension(name: "结构清晰", score: 0, feedback: "回答为空或不可评分。", evidence: "（无可引用内容）", missedPoint: "需要先结论后机制"),
        TestHostDimension(name: "应用与取舍", score: 0, feedback: "没有工程取舍。", evidence: "（无可引用内容）", missedPoint: "需要说明边界和成本"),
        TestHostDimension(name: "准确简洁", score: 0, feedback: "没有可判断的术语。", evidence: "（无可引用内容）", missedPoint: "需要使用准确术语")
    ]

    static let full = [
        TestHostDimension(name: "正确性", score: 100, feedback: "结论与机制准确。", evidence: "同一业务请求最多成功一次", missedPoint: nil),
        TestHostDimension(name: "覆盖度", score: 100, feedback: "覆盖了关键流程和失败场景。", evidence: "超时转入可重放的补偿队列", missedPoint: nil),
        TestHostDimension(name: "推理深度", score: 100, feedback: "解释了不变量、因果和验证方式。", evidence: "需用故障演练与数据校验验证不变量", missedPoint: nil),
        TestHostDimension(name: "结构清晰", score: 100, feedback: "结论、机制、边界和取舍层次完整。", evidence: "先定义不变量", missedPoint: nil),
        TestHostDimension(name: "应用与取舍", score: 100, feedback: "明确了可用性、吞吐量与复杂度的交换。", evidence: "最终一致性换取可用性和吞吐量", missedPoint: nil),
        TestHostDimension(name: "准确简洁", score: 100, feedback: "术语精确且信息密度高。", evidence: "指数退避和上限", missedPoint: nil)
    ]
}

private struct TestHostEvaluationScenario: View {
    let title: String
    let totalScore: Int
    let dimensions: [TestHostDimension]
    let referenceAnswer: String
    let showDetails: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(totalScore)")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(totalScore >= 80 ? .green : totalScore > 0 ? .orange : .secondary)
                    Text("/ 100 综合得分")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                TestHostRadarChart(dimensions: dimensions)

                if showDetails {
                    details
                }
            }
            .padding(18)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("评分结果")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("六维具体详情")
                .font(.headline)
            ForEach(dimensions) { dimension in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(dimension.name)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(dimension.score)/100")
                            .font(.subheadline.monospacedDigit())
                    }
                    ProgressView(value: Double(dimension.score), total: 100)
                    Text(dimension.feedback)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("原回答证据：“\(dimension.evidence)”")
                        .font(.caption)
                    if let missedPoint = dimension.missedPoint {
                        Text("本题遗漏：\(missedPoint)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Divider()
            }
            Text("满分答案")
                .font(.subheadline.weight(.semibold))
            Text(referenceAnswer)
                .textSelection(.enabled)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("evaluation.details")
    }
}

private struct TestHostRadarChart: View {
    let dimensions: [TestHostDimension]

    private let labels = ["正确性", "覆盖度", "推理深度", "表达结构", "权衡意识", "术语精确性"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("六维评分")
                .font(.headline)
            GeometryReader { proxy in
                let side = max(0, min(proxy.size.width, proxy.size.height))
                let center = CGPoint(x: side / 2, y: side / 2)
                let radius = side / 2
                Canvas { context, _ in
                    for level in 1...5 {
                        let path = polygonPath(points: ringPoints(level: Double(level) / 5, center: center, radius: radius))
                        context.stroke(path, with: .color(.secondary.opacity(0.24)), lineWidth: 1)
                    }
                    for index in labels.indices {
                        var axis = Path()
                        axis.move(to: center)
                        axis.addLine(to: point(index: index, fraction: 1, center: center, radius: radius))
                        context.stroke(axis, with: .color(.secondary.opacity(0.32)), lineWidth: 1)
                    }
                    let values = dimensions.map { min(max(Double($0.score) / 100, 0), 1) }
                    let data = (0..<labels.count).map { index in
                        point(index: index, fraction: index < values.count ? values[index] : 0, center: center, radius: radius)
                    }
                    let dataPath = polygonPath(points: data)
                    context.fill(dataPath, with: .color(Color.accentColor.opacity(0.22)))
                    context.stroke(dataPath, with: .color(.accentColor), lineWidth: 2.5)
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 170)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                ForEach(labels.indices, id: \.self) { index in
                    let score = index < dimensions.count ? dimensions[index].score : 0
                    Text("\(labels[index])  \(score)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("六维评分雷达图")
        .accessibilityValue(dimensions.map { "\($0.name) \($0.score) 分" }.joined(separator: "，"))
        .accessibilityIdentifier("evaluation.radar")
    }

    private func point(index: Int, fraction: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(labels.count)
        return CGPoint(
            x: center.x + CGFloat(cos(angle) * fraction) * radius,
            y: center.y + CGFloat(sin(angle) * fraction) * radius
        )
    }

    private func ringPoints(level: Double, center: CGPoint, radius: CGFloat) -> [CGPoint] {
        labels.indices.map { point(index: $0, fraction: level, center: center, radius: radius) }
    }

    private func polygonPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
