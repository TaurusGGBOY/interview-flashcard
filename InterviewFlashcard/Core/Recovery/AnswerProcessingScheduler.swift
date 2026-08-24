import Foundation
import SwiftData

/// Owns answer-processing tasks independently of any individual SwiftUI view.
/// A submitted answer therefore keeps progressing after the user leaves the
/// answer page, while the persisted attempt remains the source of truth for
/// History and any later presentation of the same question.
@MainActor
final class AnswerProcessingScheduler {
    private let processing: AnswerProcessingService
    private let context: ModelContext
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(processing: AnswerProcessingService, context: ModelContext) {
        self.processing = processing
        self.context = context
    }

    func schedule(attemptID: UUID) {
        guard tasks[attemptID] == nil else { return }

        let processing = self.processing
        let context = self.context
        tasks[attemptID] = Task { @MainActor [weak self] in
            defer { self?.tasks[attemptID] = nil }
            do {
                _ = try await processing.processStaged(
                    attemptID: attemptID,
                    context: context
                )
            } catch {
                // The processing service persists the failure on the attempt;
                // History and an explicit retry remain available to the user.
            }
        }
    }

    var scheduledAttemptIDs: Set<UUID> {
        Set(tasks.keys)
    }
}
