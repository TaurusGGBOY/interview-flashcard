import SwiftData
import SwiftUI

enum TrashAccessibilityID {
    static let screen = "trash.screen"
    static let row = "trash.row"
    static let restore = "trash.restore"
    static let permanentDelete = "trash.permanent-delete"
}

struct TrashView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \QuestionCardRecord.trashedAt, order: .reverse) private var cards: [QuestionCardRecord]
    @State private var cardToDelete: QuestionCardRecord?
    @State private var deletionImpact: TrashService.DeletionImpact?
    @State private var showPermanentConfirmation = false
    @State private var errorMessage: String?

    private var trashedCards: [QuestionCardRecord] { cards.filter { $0.trashedAt != nil } }

    var body: some View {
        List {
            if trashedCards.isEmpty {
                ContentUnavailableView("回收站为空", systemImage: "trash")
            } else {
                ForEach(trashedCards, id: \.id) { card in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(card.questionText)
                            .lineLimit(3)
                        Text("回答 \(card.attempts.count) 条 · 删除于 \(card.trashedAt!, format: .dateTime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("恢复") { restore(card) }
                                .accessibilityIdentifier(TrashAccessibilityID.restore)
                            Spacer()
                            Button("永久删除", role: .destructive) { preparePermanentDelete(card) }
                                .accessibilityIdentifier(TrashAccessibilityID.permanentDelete)
                        }
                    }
                    .accessibilityIdentifier("\(TrashAccessibilityID.row).\(card.id.uuidString)")
                }
            }
        }
        .navigationTitle("回收站")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭", systemImage: "xmark") {
                    dismiss()
                }
                .accessibilityIdentifier("trash.close")
            }
        }
        .accessibilityIdentifier(TrashAccessibilityID.screen)
        .alert("无法完成操作", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .confirmationDialog(
            "永久删除题目？",
            isPresented: $showPermanentConfirmation,
            titleVisibility: .visible
        ) {
            Button("永久删除", role: .destructive) { permanentlyDelete() }
            Button("取消", role: .cancel) { clearSelection() }
        } message: {
            Text(deletionImpact?.summary ?? "此操作不可撤销。")
        }
    }

    private func restore(_ card: QuestionCardRecord) {
        do {
            try TrashService().restore(cardID: card.id, context: context)
        } catch { errorMessage = error.localizedDescription }
    }

    private func preparePermanentDelete(_ card: QuestionCardRecord) {
        do {
            cardToDelete = card
            deletionImpact = try TrashService().deletionImpact(cardID: card.id, context: context)
            showPermanentConfirmation = true
        } catch { errorMessage = error.localizedDescription }
    }

    private func permanentlyDelete() {
        guard let cardToDelete else { return }
        Task { @MainActor in
            do {
                try await TrashService().permanentlyDelete(cardID: cardToDelete.id, context: context)
                clearSelection()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func clearSelection() {
        cardToDelete = nil
        deletionImpact = nil
        showPermanentConfirmation = false
    }
}
