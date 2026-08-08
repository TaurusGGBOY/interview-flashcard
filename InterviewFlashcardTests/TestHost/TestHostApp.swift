import SwiftUI

@main
struct InterviewFlashcardTestHost: App {
    var body: some Scene {
        WindowGroup {
            TabView {
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
