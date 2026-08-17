import SwiftData
import SwiftUI

enum OthersAccessibilityID {
    static let screen = "reclassification.others.screen"
    static let count = "reclassification.others.count"
}

struct OthersView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var cards: [QuestionCardRecord]

    private var activeOthersCount: Int {
        cards.filter { !$0.isTrashed && $0.topic.systemKind == .others }.count
    }

    var body: some View {
        List {
            Section {
                LabeledContent("待分类题目", value: "\(activeOthersCount) 道")
                    .accessibilityIdentifier(OthersAccessibilityID.count)
            } footer: {
                Text("请在题库中长按或进入选择模式，批量选择题目后移动到目标 Topic。")
            }
        }
        .navigationTitle("待分类（Others）")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭", systemImage: "xmark") {
                    dismiss()
                }
                .accessibilityIdentifier("reclassification.others.close")
            }
        }
        .accessibilityIdentifier(OthersAccessibilityID.screen)
    }
}
