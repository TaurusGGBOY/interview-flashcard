@preconcurrency import AVFoundation
import CryptoKit
import Foundation

struct RecordedAudio: Sendable, Equatable {
    let fileURL: URL
    let relativePath: String
    let format: String
    let duration: Double
    let byteCount: Int64
    let checksum: String

    init(
        fileURL: URL,
        relativePath: String,
        format: String = "m4a",
        duration: Double,
        byteCount: Int64,
        checksum: String
    ) {
        self.fileURL = fileURL
        self.relativePath = relativePath
        self.format = format
        self.duration = duration
        self.byteCount = byteCount
        self.checksum = checksum
    }
}

enum AudioRecordingError: LocalizedError, Sendable, Equatable {
    case microphonePermissionDenied
    case alreadyRecording
    case notRecording
    case unableToStart
    case unableToReadRecording(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "没有麦克风权限，请在系统设置中允许后重试。"
        case .alreadyRecording:
            "录音已经开始。"
        case .notRecording:
            "当前没有正在进行的录音。"
        case .unableToStart:
            "无法启动本地录音。"
        case let .unableToReadRecording(message):
            "无法读取本地录音：\(message)"
        }
    }
}

protocol AudioRecording: Sendable {
    func start() async throws -> URL
    func stop() async throws -> RecordedAudio
    func cancel() async
}

actor M4AAudioRecorder: AudioRecording {
    private let fileManager: FileManager
    private let applicationSupportURL: URL
    private var recorder: AVAudioRecorder?
    private var draftURL: URL?

    init(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.applicationSupportURL = applicationSupportURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("InterviewFlashcard", isDirectory: true)
    }

    func start() async throws -> URL {
        guard recorder == nil else { throw AudioRecordingError.alreadyRecording }
        guard await requestMicrophonePermission() else {
            throw AudioRecordingError.microphonePermissionDenied
        }

        let audioDirectory = applicationSupportURL.appendingPathComponent("Audio", isDirectory: true)
        try fileManager.createDirectory(
            at: audioDirectory,
            withIntermediateDirectories: true
        )
        let fileURL = audioDirectory
            .appendingPathComponent(UUID().uuidString.lowercased())
            .appendingPathExtension("m4a")

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)
        #endif

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let newRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        newRecorder.prepareToRecord()
        guard newRecorder.record() else {
            deactivateAudioSession()
            throw AudioRecordingError.unableToStart
        }
        recorder = newRecorder
        draftURL = fileURL
        return fileURL
    }

    func stop() async throws -> RecordedAudio {
        guard let recorder, let draftURL else { throw AudioRecordingError.notRecording }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        deactivateAudioSession()

        do {
            let attributes = try fileManager.attributesOfItem(atPath: draftURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let data = try Data(contentsOf: draftURL, options: .mappedIfSafe)
            let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return RecordedAudio(
                fileURL: draftURL,
                relativePath: "Audio/\(draftURL.lastPathComponent)",
                duration: duration,
                byteCount: byteCount,
                checksum: checksum
            )
        } catch {
            throw AudioRecordingError.unableToReadRecording(error.localizedDescription)
        }
    }

    func cancel() async {
        recorder?.stop()
        recorder = nil
        deactivateAudioSession()
        if let draftURL {
            try? fileManager.removeItem(at: draftURL)
        }
        draftURL = nil
    }

    private func requestMicrophonePermission() async -> Bool {
        #if os(iOS)
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        true
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        #endif
    }
}

/// Creates a deterministic local draft for Simulator acceptance without claiming
/// that the Simulator performed genuine on-device speech recognition.
actor FixtureAudioRecorder: AudioRecording {
    private let fileManager: FileManager
    private let applicationSupportURL: URL
    private var draftURL: URL?

    init(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.applicationSupportURL = applicationSupportURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("InterviewFlashcard", isDirectory: true)
    }

    func start() async throws -> URL {
        guard draftURL == nil else { throw AudioRecordingError.alreadyRecording }
        let audioDirectory = applicationSupportURL.appendingPathComponent("Audio", isDirectory: true)
        try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let url = audioDirectory
            .appendingPathComponent("fixture-\(UUID().uuidString.lowercased())")
            .appendingPathExtension("m4a")
        try Data("interview-flashcard-fixture-audio".utf8).write(to: url, options: .atomic)
        draftURL = url
        return url
    }

    func stop() async throws -> RecordedAudio {
        guard let draftURL else { throw AudioRecordingError.notRecording }
        let data = try Data(contentsOf: draftURL)
        return RecordedAudio(
            fileURL: draftURL,
            relativePath: "Audio/\(draftURL.lastPathComponent)",
            duration: 1.25,
            byteCount: Int64(data.count),
            checksum: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    func cancel() async {
        if let draftURL {
            try? fileManager.removeItem(at: draftURL)
        }
        draftURL = nil
    }
}
