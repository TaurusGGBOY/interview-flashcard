import SwiftData
import SwiftUI

struct TopicEditorView: View {
    enum Mode {
        case create
        case rename(TopicRecord)

        var title: String {
            switch self {
            case .create: "新建 Topic"
            case .rename: "重命名 Topic"
            }
        }

        var initialName: String {
            switch self {
            case .create: ""
            case let .rename(topic): topic.name
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isNameFocused: Bool

    private let mode: Mode
    private let service: TopicService
    @State private var name: String
    @State private var validationMessage: String?

    init(mode: Mode, service: TopicService = TopicService()) {
        self.mode = mode
        self.service = service
        _name = State(initialValue: mode.initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("例如：Java", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .accessibilityIdentifier(LibraryAccessibilityID.topicNameField)

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier(LibraryAccessibilityID.topicValidation)
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .accessibilityIdentifier(LibraryAccessibilityID.topicEditorCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .accessibilityIdentifier(LibraryAccessibilityID.topicEditorSave)
                }
            }
            .onAppear { isNameFocused = true }
        }
        .accessibilityIdentifier(LibraryAccessibilityID.topicEditor)
    }

    private func save() {
        validationMessage = nil
        do {
            switch mode {
            case .create:
                try service.create(name: name, context: modelContext)
            case let .rename(topic):
                try service.rename(topic, to: name, context: modelContext)
            }
            dismiss()
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
