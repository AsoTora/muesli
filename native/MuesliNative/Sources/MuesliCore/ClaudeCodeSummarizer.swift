import Foundation

public enum ClaudeCodeAuthenticationStatus: Equatable {
    case unavailable
    case signedIn
    case signedOut
    case unknown
}

public enum ClaudeCodeSummaryError: LocalizedError {
    case unavailable
    case inputTooLarge
    case timedOut
    case failed(String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Claude Code could not be found at the configured executable path."
        case .inputTooLarge:
            return "The meeting prompt exceeds Claude Code's 10 MB stdin limit."
        case .timedOut:
            return "Claude Code took too long to generate meeting notes."
        case .failed(let message):
            return "Claude Code could not generate meeting notes. \(message)"
        case .emptyResponse:
            return "Claude Code returned an empty response."
        }
    }
}

/// Runs the user's locally installed Claude Code without a shell or access to meeting files.
public enum ClaudeCodeSummarizer {
    private static let maximumInputBytes = 10_000_000
    private static let maximumOutputBytes = 5_000_000

    public static func executableURL(configuredPath: String = "") -> URL? {
        let path = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty {
            let expanded = NSString(string: path).expandingTildeInPath
            guard expanded.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: expanded) else { return nil }
            return URL(fileURLWithPath: expanded)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
            + ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        for directory in searchPaths where directory.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("claude")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Checks the CLI's own login state without starting a model request.
    public static func authenticationStatus(executablePath: String = "") async -> ClaudeCodeAuthenticationStatus {
        guard let executable = executableURL(configuredPath: executablePath) else { return .unavailable }
        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["auth", "status"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let deadline = Date().addingTimeInterval(5)
            let timeoutWork = DispatchWorkItem {
                if process.isRunning { process.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
            do {
                try process.run()
            } catch {
                return .unknown
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeoutWork)
            process.waitUntilExit()
            timeoutWork.cancel()
            if Date() >= deadline { return .unknown }
            switch process.terminationStatus {
            case 0: return .signedIn
            case 1: return .signedOut
            default: return .unknown
            }
        }.value
    }

    public static func run(
        instructions: String,
        input: String,
        model: String = "",
        executablePath: String = "",
        timeout: TimeInterval = 300
    ) async throws -> String {
        guard let executable = executableURL(configuredPath: executablePath) else {
            throw ClaudeCodeSummaryError.unavailable
        }
        guard input.utf8.count <= maximumInputBytes else { throw ClaudeCodeSummaryError.inputTooLarge }
        try Task.checkCancellation()

        let process = Process()
        let task = Task.detached(priority: .utility) {
            try runProcess(
                process,
                executable: executable,
                instructions: instructions,
                input: input,
                model: model,
                timeout: timeout
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
            if process.isRunning { process.terminate() }
        }
    }

    private static func runProcess(
        _ process: Process,
        executable: URL,
        instructions: String,
        input: String,
        model: String,
        timeout: TimeInterval
    ) throws -> String {
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("muesli-claude-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.txt")
        let outputURL = directory.appendingPathComponent("output.json")
        let errorURL = directory.appendingPathComponent("error.txt")
        try Data(input.utf8).write(to: inputURL)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let inputHandle = try FileHandle(forReadingFrom: inputURL)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? inputHandle.close()
            try? outputHandle.close()
            try? errorHandle.close()
        }

        process.executableURL = executable
        process.currentDirectoryURL = directory
        process.standardInput = inputHandle
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        var arguments = ["-p", instructions, "--output-format", "json", "--no-session-persistence",
                         "--disable-slash-commands", "--strict-mcp-config", "--setting-sources", "user"]
        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selectedModel.isEmpty { arguments += ["--model", selectedModel] }
        arguments += ["--tools", ""]
        process.arguments = arguments
        let deadline = Date().addingTimeInterval(timeout)
        let timeoutWork = DispatchWorkItem {
            if process.isRunning { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        try Task.checkCancellation()
        try process.run()
        if Task.isCancelled { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        process.waitUntilExit()
        timeoutWork.cancel()
        try Task.checkCancellation()
        if Date() >= deadline { throw ClaudeCodeSummaryError.timedOut }

        let output = try Data(contentsOf: outputURL)
        let errorText = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
        let diagnostic = String(errorText.prefix(1200)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.count <= maximumOutputBytes else { throw ClaudeCodeSummaryError.failed("The response was too large.") }
        guard let payload = try? JSONSerialization.jsonObject(with: output) as? [String: Any] else {
            throw ClaudeCodeSummaryError.failed(diagnostic.isEmpty ? "The CLI returned invalid JSON (exit \(process.terminationStatus))." : diagnostic)
        }
        let result = (payload["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0 || payload["is_error"] as? Bool == true {
            throw ClaudeCodeSummaryError.failed(result.isEmpty ? (diagnostic.isEmpty ? "Exit \(process.terminationStatus)." : diagnostic) : String(result.prefix(1200)))
        }
        guard !result.isEmpty else { throw ClaudeCodeSummaryError.emptyResponse }
        return result
    }
}
