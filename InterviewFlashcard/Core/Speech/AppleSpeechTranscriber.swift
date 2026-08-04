import Foundation
@preconcurrency import Speech

final class AppleSpeechTranscriber: SpeechTranscribing, @unchecked Sendable {
    static let engineIdentifier = "apple-speech-on-device"

    func localCapability(locale: Locale) async -> LocalSpeechCapability {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            return .unavailable(.recognizerUnavailable)
        }
        guard recognizer.supportsOnDeviceRecognition else {
            return .unavailable(.onDeviceRecognitionUnsupported)
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .available
        case .notDetermined:
            return .authorizationRequired
        case .denied:
            return .unavailable(.authorizationDenied)
        case .restricted:
            return .unavailable(.authorizationRestricted)
        @unknown default:
            return .unavailable(.authorizationRestricted)
        }
    }

    func transcribe(fileURL: URL, locale: Locale) async throws -> SpeechTranscript {
        let authorization = await requestAuthorizationIfNeeded()
        switch authorization {
        case .authorized:
            break
        case .denied:
            throw SpeechTranscriptionError.unavailable(.authorizationDenied)
        case .restricted:
            throw SpeechTranscriptionError.unavailable(.authorizationRestricted)
        case .notDetermined:
            throw SpeechTranscriptionError.unavailable(.authorizationDenied)
        @unknown default:
            throw SpeechTranscriptionError.unavailable(.authorizationRestricted)
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechTranscriptionError.unavailable(.recognizerUnavailable)
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw SpeechTranscriptionError.unavailable(.onDeviceRecognitionUnsupported)
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        Self.configureForLocalRecognition(request)

        return try await withCheckedThrowingContinuation { continuation in
            let gate = RecognitionContinuationGate(continuation: continuation)
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    gate.resume(
                        with: .failure(
                            SpeechTranscriptionError.recognitionFailed(error.localizedDescription)
                        )
                    )
                    return
                }
                guard let result, result.isFinal else { return }

                let normalizedText = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedText.isEmpty else {
                    gate.resume(with: .failure(SpeechTranscriptionError.emptyTranscript))
                    return
                }
                let confidences = result.bestTranscription.segments.map(\.confidence)
                let confidenceSummary: String?
                if confidences.isEmpty {
                    confidenceSummary = nil
                } else {
                    let mean = confidences.reduce(0, +) / Float(confidences.count)
                    confidenceSummary = String(format: "mean=%.3f", mean)
                }
                gate.resume(
                    with: .success(
                        SpeechTranscript(
                            text: normalizedText,
                            engine: Self.engineIdentifier,
                            localeIdentifier: locale.identifier,
                            confidenceSummary: confidenceSummary
                        )
                    )
                )
            }
        }
    }

    static func configureForLocalRecognition(_ request: SFSpeechRecognitionRequest) {
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
    }

    private func requestAuthorizationIfNeeded() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

private final class RecognitionContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<SpeechTranscript, any Error>

    init(continuation: CheckedContinuation<SpeechTranscript, any Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<SpeechTranscript, any Error>) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()
        continuation.resume(with: result)
    }
}
