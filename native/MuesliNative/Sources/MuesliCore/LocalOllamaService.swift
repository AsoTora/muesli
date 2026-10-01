import AppKit
import Foundation

public enum LocalOllamaError: LocalizedError, Sendable {
    case notInstalled
    case unavailable
    case missingModel(String)
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Install Ollama once, then click Set up local summaries."
        case .unavailable:
            return "Ollama did not become ready. Open Ollama and try again."
        case .missingModel(let model):
            return "\(model) is not downloaded. Click Set up local summaries in Settings to download it once."
        case .requestFailed(let message):
            return "Ollama: \(message)"
        }
    }
}

/// Starts the installed macOS app on demand. Downloads require a setup action.
public actor LocalOllamaService {
    public static let shared = LocalOllamaService()
    public static let defaultModel = "gemma3:4b"
    private let request: @Sendable (URLRequest) async throws -> Data
    private let launch: @Sendable () async throws -> Void
    private let pause: @Sendable () async throws -> Void
    private var startup: Task<Void, Error>?

    public init() {
        request = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.error
                throw LocalOllamaError.requestFailed(message ?? "Request failed. Check the server address.")
            }
            return data
        }
        launch = { try await Self.launchApplication() }
        pause = { try await Task.sleep(nanoseconds: 500_000_000) }
    }

    init(
        request: @escaping @Sendable (URLRequest) async throws -> Data,
        launch: @escaping @Sendable () async throws -> Void,
        pause: @escaping @Sendable () async throws -> Void
    ) {
        self.request = request
        self.launch = launch
        self.pause = pause
    }

    public static func baseURL(_ address: String) throws -> URL {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address.isEmpty ? "http://localhost:11434" : address),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            throw LocalOllamaError.requestFailed("Invalid server address.")
        }
        return url
    }

    public static func canStartLocalApp(for url: URL) -> Bool {
        url.scheme?.lowercased() == "http"
            && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(url.host?.lowercased() ?? "")
            && url.port == 11434
            && ["", "/"].contains(url.path)
            && url.user == nil && url.password == nil
    }

    public func installedModels(at url: URL) async throws -> [String] {
        var query = URLRequest(url: url.appendingPathComponent("api/tags"))
        query.timeoutInterval = 2
        let data = try await request(query)
        return try JSONDecoder().decode(ModelList.self, from: data).models.map(\.name)
    }

    public func ensureReady(at url: URL, model: String, downloadMissing: Bool = false) async throws {
        var models: [String]
        do {
            models = try await installedModels(at: url)
        } catch {
            try Task.checkCancellation()
            guard Self.canStartLocalApp(for: url) else { throw error }
            try await start(at: url)
            models = try await installedModels(at: url)
        }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = model.isEmpty ? Self.defaultModel : model
        guard !models.contains(where: { Self.canonical($0) == Self.canonical(selected) }) else { return }
        guard downloadMissing else { throw LocalOllamaError.missingModel(selected) }

        var pull = URLRequest(url: url.appendingPathComponent("api/pull"))
        pull.httpMethod = "POST"
        pull.timeoutInterval = 3600
        pull.setValue("application/json", forHTTPHeaderField: "Content-Type")
        pull.httpBody = try JSONSerialization.data(withJSONObject: ["model": selected, "stream": false])
        let data = try await request(pull)
        if let error = try? JSONDecoder().decode(ServerError.self, from: data) {
            throw LocalOllamaError.requestFailed(error.error)
        }
        let installed = try await installedModels(at: url)
        guard installed.contains(where: { Self.canonical($0) == Self.canonical(selected) }) else {
            throw LocalOllamaError.missingModel(selected)
        }
    }

    /// Custom servers keep their existing connection behavior and lifecycle.
    public func prepareForSummary(at url: URL, model: String) async throws {
        guard Self.canStartLocalApp(for: url) else { return }
        try await ensureReady(at: url, model: model)
    }

    private func start(at url: URL) async throws {
        if let startup { return try await startup.value }
        if (try? await installedModels(at: url)) != nil { return }
        if let startup { return try await startup.value }
        let task = Task {
            try await launch()
            for _ in 0..<40 {
                try Task.checkCancellation()
                if (try? await installedModels(at: url)) != nil { return }
                try await pause()
            }
            throw LocalOllamaError.unavailable
        }
        startup = task
        defer { startup = nil }
        try await task.value
    }

    private static func canonical(_ model: String) -> String {
        model.split(separator: "/").last?.contains(":") == true ? model : model + ":latest"
    }

    @MainActor private static func launchApplication() async throws {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.electron.ollama") else {
            throw LocalOllamaError.notInstalled
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private struct ModelList: Decodable { let models: [Model] }
    private struct Model: Decodable { let name: String }
    private struct ServerError: Decodable { let error: String }
}
