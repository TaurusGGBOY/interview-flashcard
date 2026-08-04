import Foundation

enum LocalSpeechUnavailableReason: String, Codable, Error, Sendable, Equatable {
    case authorizationDenied
    case authorizationRestricted
    case recognizerUnavailable
    case onDeviceRecognitionUnsupported
    case onDeviceModelMissing

    var userMessage: String {
        switch self {
        case .authorizationDenied:
            "没有语音识别权限，请在系统设置中允许后重试。"
        case .authorizationRestricted:
            "当前设备限制了语音识别。"
        case .recognizerUnavailable:
            "当前语言的语音识别器不可用。"
        case .onDeviceRecognitionUnsupported:
            "当前设备无法本地转写。"
        case .onDeviceModelMissing:
            "当前语言的本地转写模型尚未安装。"
        }
    }
}

enum LocalSpeechCapability: Sendable, Equatable {
    case available
    case authorizationRequired
    case unavailable(LocalSpeechUnavailableReason)

    var canStartVoiceAnswer: Bool {
        switch self {
        case .available, .authorizationRequired:
            true
        case .unavailable:
            false
        }
    }
}

struct SpeechTranscript: Codable, Sendable, Equatable {
    let text: String
    let engine: String
    let localeIdentifier: String
    let confidenceSummary: String?

    init(
        text: String,
        engine: String = "apple-speech-on-device",
        localeIdentifier: String,
        confidenceSummary: String? = nil
    ) {
        self.text = text
        self.engine = engine
        self.localeIdentifier = localeIdentifier
        self.confidenceSummary = confidenceSummary
    }
}

enum SpeechTranscriptionError: LocalizedError, Sendable, Equatable {
    case unavailable(LocalSpeechUnavailableReason)
    case emptyTranscript
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(reason):
            reason.userMessage
        case .emptyTranscript:
            "没有识别到可用文字，请重新录制。"
        case let .recognitionFailed(message):
            "本地转写失败：\(message)"
        }
    }
}

protocol SpeechTranscribing: Sendable {
    func localCapability(locale: Locale) async -> LocalSpeechCapability
    func transcribe(fileURL: URL, locale: Locale) async throws -> SpeechTranscript
}

struct VoiceAvailability: Sendable {
    let transcriber: any SpeechTranscribing

    func isEnabled(locale: Locale) async -> Bool {
        await transcriber.localCapability(locale: locale).canStartVoiceAnswer
    }
}

/// Deterministic implementation used by unit tests and DEBUG acceptance launches.
struct FixtureSpeechTranscriber: SpeechTranscribing {
    let capability: LocalSpeechCapability
    let transcript: SpeechTranscript
    let transcriptionError: SpeechTranscriptionError?

    init(
        capability: LocalSpeechCapability,
        transcript: SpeechTranscript = SpeechTranscript(
            text: "JVM 会加载类",
            localeIdentifier: "zh-CN",
            confidenceSummary: "fixture"
        ),
        transcriptionError: SpeechTranscriptionError? = nil
    ) {
        self.capability = capability
        self.transcript = transcript
        self.transcriptionError = transcriptionError
    }

    func localCapability(locale: Locale) async -> LocalSpeechCapability {
        capability
    }

    func transcribe(fileURL: URL, locale: Locale) async throws -> SpeechTranscript {
        if let transcriptionError {
            throw transcriptionError
        }
        guard capability.canStartVoiceAnswer else {
            if case let .unavailable(reason) = capability {
                throw SpeechTranscriptionError.unavailable(reason)
            }
            throw SpeechTranscriptionError.unavailable(.recognizerUnavailable)
        }
        return transcript
    }
}
