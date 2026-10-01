import Foundation
import Testing
@testable import MuesliCore

@Suite("Local meeting summary requests")
struct OllamaMeetingRequestTests {
    @Test("a Russian source sets a language default without overriding a user's language choice")
    func sourceLanguage() {
        let source = "Обсуждали результаты опросника и разные предположения. Участник не согласился с одним из объяснений. Следующая встреча в четверг."
        let instructions = MeetingSummaryGrounding.languageInstructions(for: source)
        #expect(instructions.contains("Russian (ru)"))
        #expect(instructions.contains("only when the user explicitly requests another output language"))
        #expect(instructions.contains("headings in a template specify structure"))
    }

    @Test("a long multilingual meeting reaches the local model without clipping")
    func completeTranscript() throws {
        let transcript = String(repeating: "[13:01] Speaker 1: Обсуждаем разные варианты, решение пока не принято.\n", count: 1_000)
            + "[13:54] Speaker 2: Следующая встреча в четверг в 13 часов."
        let body = OllamaMeetingRequest.body(model: "qwen3.5:9b", instructions: "Use only source facts.", prompt: transcript, outputTokens: 3_500)
        let data = try JSONSerialization.data(withJSONObject: body)
        let decoded = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(decoded["messages"] as? [[String: String]])
        #expect(messages.last?["content"] == transcript)
        let options = try #require(decoded["options"] as? [String: Any])
        #expect(options["num_ctx"] as? Int == 32_768)
        #expect(options["num_predict"] as? Int == 3_500)
        #expect(options["temperature"] as? Double == 0.0)
    }

    @Test("Qwen and Gemma 4 use their budget for notes while other models retain their thinking setting", arguments: ["qwen3.5:4b", "Qwen3.5:9b", "qwen3.6:35b", "gemma4:12b", "gemma4:26b", "gemma3:4b", "custom"])
    func thinkingBudget(model: String) {
        let body = OllamaMeetingRequest.body(model: model, instructions: "Summary", prompt: "Hello", outputTokens: 100)
        if model.lowercased().hasPrefix("qwen3") || model.lowercased().hasPrefix("gemma4") {
            #expect(body["think"] as? Bool == false)
        } else {
            #expect(body["think"] == nil)
        }
    }

    @Test("incomplete or reasoning-only responses cannot replace saved notes", arguments: [
        ###"{"message":{"content":"## Summary\n- Partial"},"done_reason":"length"}"###,
        ###"{"message":{"content":"  ","thinking":"Hidden reasoning"},"done_reason":"stop"}"###,
        ###"{"error":"Model failed"}"###,
        ###"{"message":{"content":"Partial response"},"done":false}"###,
        ###"{"message":{"content":"Notes from a clipped source"},"done_reason":"stop","prompt_eval_count":32760}"###,
    ])
    func rejectsIncomplete(json: String) {
        #expect(throws: LocalOllamaError.self) {
            try OllamaMeetingRequest.completedContent(from: Data(json.utf8))
        }
    }

    @Test("complete notes preserve their original language and markdown")
    func completeNotes() throws {
        let json = ###"{"message":{"content":"  ## Итоги\n- Встреча в четверг.\n"},"done_reason":"stop"}"###
        #expect(try OllamaMeetingRequest.completedContent(from: Data(json.utf8)) == "## Итоги\n- Встреча в четверг.")
    }
}
