import SwiftUI
import UIKit

struct JSONTemplateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    static let template = """
    {
      "formatVersion": 1,
      "questions": [
        {
          "question": "请解释 Swift Concurrency 中 async/await 的作用。",
          "topic": "Swift",
          "answer": "async/await 用于以结构化方式表达异步任务，减少回调嵌套，并让错误处理更清晰。"
        }
      ]
    }
    """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("JSON 题库模板", systemImage: "curlybraces.square")
                        .font(.headline)
                    Text("顶层固定使用 questions 数组；每道题都需要题目、Topic 和满分答案。formatVersion 固定为 1。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(Self.template)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier(ImportAccessibilityID.jsonTemplateCode)

                VStack(alignment: .leading, spacing: 8) {
                    Text("字段说明")
                        .font(.headline)
                    Text("• formatVersion：填写 1")
                    Text("• question：面试题目")
                    Text("• topic：主题名称，不存在时会自动创建")
                    Text("• answer：这道题的满分参考答案")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .safeAreaPadding(.horizontal, 20)
            .safeAreaPadding(.vertical, 16)
        }
        .navigationTitle("JSON 格式示例")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(didCopy ? "已复制" : "复制模板", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = Self.template
                    didCopy = true
                }
                .accessibilityIdentifier(ImportAccessibilityID.jsonTemplateCopyButton)
            }
        }
        .accessibilityIdentifier(ImportAccessibilityID.jsonTemplateScreen)
    }
}
