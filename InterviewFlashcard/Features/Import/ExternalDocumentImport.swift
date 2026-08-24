import Foundation
import Observation

public struct ExternalDocumentImportRequest: Identifiable, Equatable {
    public let id: UUID
    public let urls: [URL]

    public init(id: UUID = UUID(), urls: [URL]) {
        self.id = id
        self.urls = urls
    }
}

enum ExternalDocumentImportKind: Equatable {
    case markdown
    case json
}

enum ExternalDocumentImportError: LocalizedError, Equatable {
    case unsupportedFile(URL)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFile(url):
            "不支持的文件类型：\(url.lastPathComponent)。仅支持 Markdown（.md）和 JSON（.json）。"
        }
    }
}

enum ExternalDocumentImportRouter {
    static func kind(for url: URL) -> ExternalDocumentImportKind? {
        switch url.pathExtension.lowercased() {
        case "md": .markdown
        case "json": .json
        default: nil
        }
    }

    static func classify(
        urls: [URL]
    ) -> (markdown: [URL], json: [URL], unsupported: [URL]) {
        urls.reduce(into: (markdown: [URL](), json: [URL](), unsupported: [URL]())) { result, url in
            switch kind(for: url) {
            case .markdown:
                result.markdown.append(url)
            case .json:
                result.json.append(url)
            case nil:
                result.unsupported.append(url)
            }
        }
    }
}

@MainActor
@Observable
public final class ExternalDocumentImportInbox {
    public private(set) var pendingRequest: ExternalDocumentImportRequest?

    public init() {}

    public func receive(_ url: URL) {
        receive([url])
    }

    public func receive(_ urls: [URL]) {
        var knownURLs = Set(pendingRequest?.urls.map(\.absoluteString) ?? [])
        let newURLs = urls.filter { knownURLs.insert($0.absoluteString).inserted }
        guard !newURLs.isEmpty else { return }

        if let pendingRequest {
            self.pendingRequest = ExternalDocumentImportRequest(
                id: pendingRequest.id,
                urls: pendingRequest.urls + newURLs
            )
        } else {
            pendingRequest = ExternalDocumentImportRequest(urls: newURLs)
        }
    }

    public func consume(requestID: UUID) {
        guard pendingRequest?.id == requestID else { return }
        pendingRequest = nil
    }
}
