import SwiftData
import SwiftUI

struct JSONImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var topics: [TopicRecord]

    let draft: JSONQuestionImportDraft
    let onConfirm: (JSONQuestionImportDraft) throws -> ImportRunRecord

    @State private var isConfirming = false
    @State private var errorMessage: String?

    private var orderedTopicNames: [String] {
        var seen: Set<String> = []
        return draft.items.compactMap { item in
            let key = TopicNameNormalization.key(item.topicName)
            guard seen.insert(key).inserted else { return nil }
            return item.topicName
        }
    }

    private var existingTopicKeys: Set<String> {
        Set(topics.map { TopicNameNormalization.key($0.name) })
    }

    private var newTopicNames: [String] {
        orderedTopicNames.filter { !existingTopicKeys.contains(TopicNameNormalization.key($0)) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("JSON 校验已通过", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)

                    Text("\(draft.fileName) 中共有 \(draft.items.count) 道题目，涉及 \(orderedTopicNames.count) 个 Topic。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if newTopicNames.isEmpty {
                        Text("全部使用题库中已有的 Topic。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("将新建 Topic：\(newTopicNames.joined(separator: "、"))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: confirm) {
                        Label("一键导入全部题目", systemImage: "tray.and.arrow.down.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConfirming)
                    .accessibilityIdentifier(ImportAccessibilityID.jsonConfirmButton)
                }
                .padding(.vertical, 4)
            }

            Section("将导入的题目（\(draft.items.count)）") {
                ForEach(draft.items) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.question)
                        Text(item.topicName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.answer)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("导入内容")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭", systemImage: "xmark") { dismiss() }
            }
        }
        .overlay {
            if isConfirming {
                ProgressView("正在导入题库…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("导入失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .accessibilityIdentifier(ImportAccessibilityID.jsonPreviewScreen)
    }

    private func confirm() {
        isConfirming = true
        defer { isConfirming = false }
        do {
            _ = try onConfirm(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct JSONImportBatchPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var topics: [TopicRecord]

    let drafts: [JSONQuestionImportDraft]
    let onConfirm: ([JSONQuestionImportDraft]) throws -> [ImportRunRecord]

    @State private var isConfirming = false
    @State private var errorMessage: String?

    private var totalQuestionCount: Int {
        drafts.reduce(0) { $0 + $1.items.count }
    }

    private var orderedTopicNames: [String] {
        var seen: Set<String> = []
        return drafts.flatMap(\.items).compactMap { item in
            let key = TopicNameNormalization.key(item.topicName)
            guard seen.insert(key).inserted else { return nil }
            return item.topicName
        }
    }

    private var existingTopicKeys: Set<String> {
        Set(topics.map { TopicNameNormalization.key($0.name) })
    }

    private var newTopicNames: [String] {
        orderedTopicNames.filter { !existingTopicKeys.contains(TopicNameNormalization.key($0)) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("全部 JSON 校验已通过", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)

                    Text("已选择 \(drafts.count) 个文件，共 \(totalQuestionCount) 道题目，涉及 \(orderedTopicNames.count) 个 Topic。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if newTopicNames.isEmpty {
                        Text("全部使用题库中已有的 Topic。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("将新建 Topic：\(newTopicNames.joined(separator: "、"))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: confirm) {
                        Label("导入全部 \(drafts.count) 个文件", systemImage: "tray.full.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConfirming)
                    .accessibilityIdentifier(ImportAccessibilityID.jsonBatchConfirmButton)
                }
                .padding(.vertical, 4)
            }

            Section("将导入的文件") {
                ForEach(Array(drafts.enumerated()), id: \.offset) { _, draft in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.fileName)
                            .font(.headline)
                        Text("\(draft.items.count) 道题目")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("批量导入内容")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭", systemImage: "xmark") { dismiss() }
            }
        }
        .overlay {
            if isConfirming {
                ProgressView("正在批量导入题库…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("导入失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .accessibilityIdentifier(ImportAccessibilityID.jsonBatchPreviewScreen)
    }

    private func confirm() {
        isConfirming = true
        defer { isConfirming = false }
        do {
            _ = try onConfirm(drafts)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct JSONImportValidationView: View {
    @Environment(\.dismiss) private var dismiss
    let error: JSONQuestionImportValidationError

    var body: some View {
        List {
            Section {
                Label("文件没有导入", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.headline)
                Text("请修改原 JSON 文件后重新选择。题库没有发生变化。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("发现 \(error.issues.count) 个问题") {
                ForEach(Array(error.issues.enumerated()), id: \.offset) { _, issue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(issue.message)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("无法导入 JSON")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭", systemImage: "xmark") { dismiss() }
            }
        }
        .accessibilityIdentifier(ImportAccessibilityID.jsonValidationScreen)
    }
}
