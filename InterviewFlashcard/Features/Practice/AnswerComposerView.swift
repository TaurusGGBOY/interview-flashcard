import SwiftUI

/// The single text input for answers. It keeps the primary action close to the
/// editor while allowing the whole screen to scroll with the keyboard visible.
struct AnswerComposerView: View {
    @Binding var text: String
    let isSubmitting: Bool
    let onSubmit: () -> Void

    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("你的回答", systemImage: "text.alignleft")
                .font(.headline)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .focused($isEditorFocused)
                    .frame(minHeight: 190)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier(AnswerEditorAccessibilityID.textEditor)

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("先用自己的话回答，提交后才会显示评分和满分答案")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)
                        .allowsHitTesting(false)
                }
            }

            Button {
                isEditorFocused = false
                onSubmit()
            } label: {
                Label("提交回答", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier(AnswerEditorAccessibilityID.submit)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Keep the primary action reachable while the keyboard is shown.
        // The scroll view can still pan, but the keyboard toolbar guarantees
        // that submitting does not depend on first dismissing the keyboard.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("提交回答", systemImage: "paperplane.fill") {
                    isEditorFocused = false
                    onSubmit()
                }
                .disabled(isSubmitting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("\(AnswerEditorAccessibilityID.submit).keyboard")
            }
        }
    }
}
