import Foundation
import SwiftData

/// Resumes only work that is safe to infer from persisted state. Failed imports and
/// failed attempts remain visible for explicit user retry; Others reclassification
/// is deliberately never started automatically.
@MainActor
struct LaunchRecoveryCoordinator {
    let importer: ImportCoordinator?
    let processing: AnswerProcessingService?

    init(importer: ImportCoordinator? = nil, processing: AnswerProcessingService? = nil) {
        self.importer = importer
        self.processing = processing
    }

    func resume(context: ModelContext) async {
        if let importer {
            let runs = (try? context.fetch(FetchDescriptor<ImportRunRecord>())) ?? []
            for run in runs where isResumable(run.status) {
                try? await importer.continueRun(id: run.id)
            }
        }

        guard let processing else { return }
        let attempts = (try? context.fetch(FetchDescriptor<AnswerAttemptRecord>())) ?? []
        for attempt in attempts where isPending(attempt.processingStatus) && attempt.question.trashedAt == nil {
            do {
                _ = try await processing.resume(attemptID: attempt.id, context: context)
            } catch {
                // The service persists failed state; recovery must not retry forever.
            }
        }
    }

    private func isResumable(_ status: ImportRunStatus) -> Bool {
        switch status {
        case .queued, .chunking, .decomposing, .refining, .activating:
            true
        case .ready, .active, .failed:
            false
        }
    }

    private func isPending(_ status: AttemptProcessingStatus) -> Bool {
        switch status {
        case .saved, .scoring, .feedback, .referenceAnswer, .polishing, .evaluating:
            true
        case .completed, .failed:
            false
        }
    }
}
