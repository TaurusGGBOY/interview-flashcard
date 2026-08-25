import SwiftUI

struct QuestionCardView: View {
    let card: QuestionCardSnapshot

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: QuestionCardTheme {
        QuestionCardTheme.theme(for: card.id)
    }

    var body: some View {
        GeometryReader { proxy in
            let questionAreaHeight = max(proxy.size.height - 132, 180)

            ZStack {
                theme.gradient(for: colorScheme)

                decorativeLayer

                VStack(spacing: 0) {
                    topicHeader

                    Spacer(minLength: 14)

                    ViewThatFits(in: .vertical) {
                        questionText(font: .system(.title2, design: .rounded, weight: .bold), minHeight: questionAreaHeight)
                        questionText(font: .system(.title3, design: .rounded, weight: .bold), minHeight: questionAreaHeight)
                        questionText(font: .system(.body, design: .rounded, weight: .semibold), minHeight: questionAreaHeight)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Spacer(minLength: 14)

                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right")
                        Text("左右滑动选择操作 · 上划删除本题")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.foreground.opacity(0.88))
                    .accessibilityHidden(true)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(theme.foreground.opacity(0.24), lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.32 : 0.18),
                radius: 22,
                y: 10
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(PracticeAccessibilityID.card)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: colorScheme)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topicHeader: some View {
        HStack(spacing: 10) {
            Label("主题", systemImage: "square.stack.3d.up.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.foreground.opacity(0.82))

            Text(card.topicName)
                .font(.headline.weight(.bold))
                .foregroundStyle(theme.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Text("面试题")
                Text(card.questionNumber.map { "No.\($0)" } ?? "No.—")
                    .accessibilityLabel(card.questionNumber.map { "题号 \($0)" } ?? "暂无题号")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.foreground.opacity(0.78))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.foreground.opacity(0.14), in: Capsule())
        }
        .frame(minHeight: 44)
    }

    private func questionText(font: Font, minHeight: CGFloat) -> some View {
        Text(card.questionText)
            .font(font)
            .multilineTextAlignment(.center)
            .foregroundStyle(theme.foreground)
            .allowsTightening(true)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(PracticeAccessibilityID.question)
            .padding(.horizontal, 20)
    }

    private var decorativeLayer: some View {
        ZStack {
            Circle()
                .fill(theme.accent.opacity(0.13))
                .frame(width: 230, height: 230)
                .blur(radius: 2)
                .offset(x: 150, y: -180)

            Circle()
                .stroke(theme.accent.opacity(0.14), lineWidth: 26)
                .frame(width: 180, height: 180)
                .offset(x: -170, y: 210)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Question card") {
    QuestionCardView(
        card: QuestionCardSnapshot(
            id: UUID(uuidString: "e8f9c05c-2aa8-42d4-8d6d-36bce6ddbb7a")!,
            topicID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            topicName: "分布式系统",
            questionText: "请解释如何设计一个支持水平扩展、幂等写入和故障恢复的订单服务，并说明关键取舍。",
            questionNumber: 42,
            isTrashed: false,
            hasSubmittedAttempt: false
        )
    )
    .padding(20)
    .frame(height: 560)
}
