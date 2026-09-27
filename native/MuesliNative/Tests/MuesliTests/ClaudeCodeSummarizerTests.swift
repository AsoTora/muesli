import Foundation
import Testing
import MuesliCore
@testable import MuesliNativeApp
@testable import MuesliCLI

@Suite("Claude Code summarizer")
struct ClaudeCodeSummarizerTests {
    @Test("runs a configured executable with the prompt on stdin and parses its JSON result")
    func configuredExecutable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-claude-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fake claude")
        let script = """
        #!/bin/sh
        input=$(cat)
        case "$input" in
          *"Decision: ship"*) ;;
          *) exit 3 ;;
        esac
        printf '%s' '{"type":"result","is_error":false,"result":"## Summary\\n- Ship"}'
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let summary = try await ClaudeCodeSummarizer.run(
            instructions: "Summarize this meeting.",
            input: "Decision: ship",
            model: "sonnet",
            executablePath: executable.path,
            timeout: 5
        )
        #expect(summary == "## Summary\n- Ship")
    }

    @Test("missing explicitly configured executable gives a useful error")
    func missingExecutable() async {
        do {
            _ = try await ClaudeCodeSummarizer.run(
                instructions: "Summarize",
                input: "Transcript",
                executablePath: "/missing/muesli-test-claude"
            )
            Issue.record("Expected missing executable failure")
        } catch {
            #expect(error.localizedDescription.contains("Claude Code could not be found"))
        }
    }

    @Test("sign-in checks use the installed CLI without a model request")
    func authenticationStatus() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-claude-auth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("claude")
        try "#!/bin/sh\n[ \"$1 $2\" = \"auth status\" ] || exit 7\nexit 0\n"
            .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        #expect(await ClaudeCodeSummarizer.authenticationStatus(executablePath: executable.path) == .signedIn)

        try "#!/bin/sh\n[ \"$1 $2\" = \"auth status\" ] || exit 7\nexit 1\n"
            .write(to: executable, atomically: true, encoding: .utf8)
        #expect(await ClaudeCodeSummarizer.authenticationStatus(executablePath: executable.path) == .signedOut)
        #expect(await ClaudeCodeSummarizer.authenticationStatus(executablePath: "/missing/muesli-test-claude") == .unavailable)
    }

    @Test("the app and audio CLI route the named provider through Claude Code")
    func providerDispatch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-claude-dispatch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("claude")
        let script = """
        #!/bin/sh
        input=$(cat)
        case "$input" in
          *"Decision: ship"*) ;;
          *) exit 3 ;;
        esac
        printf '%s' '{"type":"result","is_error":false,"result":"## Summary\\n- Ship"}'
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        var appConfig = AppConfig()
        appConfig.meetingSummaryBackend = MeetingSummaryBackendOption.claudeCode.backend
        appConfig.claudeCodeExecutablePath = executable.path
        let appSummary = try await MeetingSummaryClient.summarize(
            transcript: "Decision: ship",
            meetingTitle: "Launch",
            config: appConfig
        )
        #expect(appSummary.contains("## Summary\n- Ship"))

        var cliConfig = CLISummaryConfig()
        cliConfig.meetingSummaryBackend = "claude_code"
        cliConfig.claudeCodeExecutablePath = executable.path
        let cliSummary = try await CLISummaryClient.summarize(
            transcript: "Decision: ship",
            title: "Launch",
            config: cliConfig
        )
        #expect(cliSummary == "## Summary\n- Ship")
    }

    @Test("the audio CLI decodes the app's Claude Code configuration keys")
    func cliConfiguration() throws {
        var appConfig = AppConfig()
        appConfig.meetingSummaryBackend = "claude_code"
        appConfig.claudeCodeModel = "opus"
        appConfig.claudeCodeExecutablePath = "/custom/claude"
        let cliConfig = try JSONDecoder().decode(CLISummaryConfig.self, from: JSONEncoder().encode(appConfig))
        #expect(cliConfig.meetingSummaryBackend == "claude_code")
        #expect(cliConfig.claudeCodeModel == "opus")
        #expect(cliConfig.claudeCodeExecutablePath == "/custom/claude")
    }

    @Test("a CLI error payload is not saved as meeting notes")
    func errorPayload() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-claude-error-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("claude")
        try "#!/bin/sh\nprintf '%s' '{\"type\":\"result\",\"is_error\":true,\"result\":\"Not logged in\"}'\n"
            .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        do {
            _ = try await ClaudeCodeSummarizer.run(
                instructions: "Summarize",
                input: "Transcript",
                executablePath: executable.path,
                timeout: 5
            )
            Issue.record("Expected CLI error payload to fail")
        } catch {
            #expect(error.localizedDescription.contains("Not logged in"))
        }
    }
}
