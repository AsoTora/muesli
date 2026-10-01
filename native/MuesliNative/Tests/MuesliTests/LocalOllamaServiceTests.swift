import Foundation
import Testing
@testable import MuesliCore

@Suite("Local Ollama setup")
struct LocalOllamaServiceTests {
    private let local = URL(string: "http://127.0.0.1:11434")!

    private actor Server {
        var ready: Bool
        var models: [String]
        var launches = 0
        var pulls = 0
        var pullError = false

        init(ready: Bool = true, models: [String] = ["gemma3:4b"]) {
            self.ready = ready
            self.models = models
        }

        func launch() { launches += 1; ready = true }
        func failPull() { pullError = true }
        func respond(_ request: URLRequest) throws -> Data {
            guard ready else { throw URLError(.cannotConnectToHost) }
            if request.url?.path == "/api/pull" {
                pulls += 1
                let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as! [String: Any]
                #expect(body["stream"] as? Bool == false)
                if pullError { return Data("{\"error\":\"model not found\"}".utf8) }
                models.append(try #require(body["model"] as? String))
                return Data("{\"status\":\"success\"}".utf8)
            }
            return try JSONSerialization.data(withJSONObject: ["models": models.map { ["name": $0] }])
        }

        func counts() -> (Int, Int) { (launches, pulls) }
    }

    private func service(_ server: Server) -> LocalOllamaService {
        LocalOllamaService(
            request: { try await server.respond($0) },
            launch: { await server.launch() },
            pause: { await Task.yield() }
        )
    }

    @Test("a ready installed model does not launch or download again")
    func alreadyReady() async throws {
        let server = Server()
        let service = service(server)
        try await service.ensureReady(at: local, model: "gemma3:4b", downloadMissing: true)
        try await service.prepareForSummary(at: local, model: "gemma3:4b")
        let counts = await server.counts()
        #expect(counts.0 == 0)
        #expect(counts.1 == 0)
    }

    @Test("a stopped local app starts on demand and reuses its model")
    func startsOnce() async throws {
        let server = Server(ready: false)
        let service = service(server)
        try await service.prepareForSummary(at: local, model: "gemma3:4b")
        try await service.prepareForSummary(at: local, model: "gemma3:4b")
        let counts = await server.counts()
        #expect(counts.0 == 1)
        #expect(counts.1 == 0)
    }

    @Test("missing models require a setup action and download only once")
    func explicitDownload() async throws {
        let server = Server(models: [])
        let service = service(server)
        await #expect(throws: LocalOllamaError.self) {
            try await service.prepareForSummary(at: local, model: "gemma3:4b")
        }
        #expect(await server.counts().1 == 0)
        try await service.ensureReady(at: local, model: "gemma3:4b", downloadMissing: true)
        try await service.ensureReady(at: local, model: "gemma3:4b", downloadMissing: true)
        #expect(await server.counts().1 == 1)
    }

    @Test("an implicit latest tag matches an installed model")
    func latestAlias() async throws {
        let server = Server(models: ["custom:latest"])
        try await service(server).ensureReady(at: local, model: "custom", downloadMissing: true)
        #expect(await server.counts().1 == 0)
    }

    @Test("custom endpoints never launch the local app", arguments: [
        "http://example.com:11434", "http://localhost:1234", "https://localhost:11434", "http://localhost:11434/proxy"
    ])
    func customEndpoint(address: String) async throws {
        let server = Server(ready: false)
        let url = try LocalOllamaService.baseURL(address)
        let service = service(server)
        try await service.prepareForSummary(at: url, model: "custom")
        await #expect(throws: URLError.self) {
            try await service.ensureReady(at: url, model: "custom", downloadMissing: true)
        }
        #expect(await server.counts().0 == 0)
    }

    @Test("model pull errors do not report successful setup")
    func pullFailure() async throws {
        let server = Server(models: [])
        await server.failPull()
        await #expect(throws: LocalOllamaError.self) {
            try await service(server).ensureReady(at: local, model: "missing", downloadMissing: true)
        }
    }
}
