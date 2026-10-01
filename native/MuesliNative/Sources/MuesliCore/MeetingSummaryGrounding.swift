import Foundation
import NaturalLanguage

/// Shared by the app and headless summaries so they use the same source rules.
public enum MeetingSummaryGrounding {
    public static func languageInstructions(for transcript: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(transcript)
        guard let language = recognizer.dominantLanguage,
              let name = Locale(identifier: "en").localizedString(forLanguageCode: language.rawValue) else { return "" }
        return "Default output language: \(name) (\(language.rawValue)). Write all notes and section headings in \(name). English headings in a template specify structure, not an output-language request. Override this default only when the user explicitly requests another output language.\n\n"
    }

    public static let instructions = """


    Accuracy and language rules:
    Write the notes in the dominant language of the transcript, including translated section headings, unless the user explicitly requests another output language in the template or written notes.
    Identify the actual kind and main purpose of the conversation from the full transcript. Do not assume it is a business meeting. Financial or work examples do not necessarily define its main topic.
    The transcript can contain recognition errors and duplicated speech across channels. Combine repeated content. Speaker labels alone do not prove identity, role, or the number of participants.
    Separate reported experiences, suggestions, questions, hypotheses, disagreements, and confirmed agreements. Do not turn a hypothesis into a fact or diagnosis, or a discussed option into an agreed task.
    Later clarifications and denials override earlier interpretations. Include those corrections explicitly. An action completed during the conversation is not future homework. Requests for immediate explanation or feedback are not future tasks. A question, suggestion, or the requester's repeated words do not prove acceptance by the person expected to act.
    Only list action items and decisions explicitly agreed in this conversation. Preserve dates and times exactly as stated; do not infer a missing year. Do not invent names, book titles, quotations, trackers, owners, or commitments.
    If current generated notes or a meeting title conflict with the transcript, the transcript takes priority. Omit notable quotes unless a short exact quote is both clear and useful. Say that no items were agreed when a section has no supported content.
    Cover the main topics throughout the conversation and the closing feedback, not just its opening or last topic. Be concise and specific; avoid speculation.
    """
}

public enum OllamaMeetingRequest {
    public static let summaryOutputTokens = 3_500
    public static let contextTokens = 32_768

    public static func body(model: String, instructions: String, prompt: String, outputTokens: Int) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt],
            ],
            "stream": false,
            // Do not depend on Ollama's device-specific context default.
            "options": ["num_predict": outputTokens, "num_ctx": contextTokens, "temperature": 0.0, "presence_penalty": 0.0],
        ]
        if model.lowercased().hasPrefix("qwen3") || model.lowercased().hasPrefix("gemma4") {
            // Reasoning can consume the output budget without returning notes.
            body["think"] = false
        }
        return body
    }

    /// A partial response must never replace a saved meeting's complete notes.
    public static func completedContent(from data: Data) throws -> String {
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let error = response.error {
            throw LocalOllamaError.requestFailed(error)
        }
        guard response.done != false, response.doneReason != "length" else {
            throw LocalOllamaError.requestFailed("The model reached its output limit. The incomplete notes were not saved. Use a shorter note template and try again.")
        }
        // Ollama can clip an oversized prompt to its context window. A result
        // at that boundary cannot prove that the complete source was read.
        if let promptTokens = response.promptTokens, promptTokens >= contextTokens - 512 {
            throw LocalOllamaError.requestFailed("The transcript reached the local model's context limit. The notes were not saved because part of the meeting may be missing.")
        }
        let content = response.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else {
            throw LocalOllamaError.requestFailed("The model returned no notes. Try another local model.")
        }
        return content
    }

    private struct Response: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message?
        let doneReason: String?
        let done: Bool?
        let promptTokens: Int?
        let error: String?
        enum CodingKeys: String, CodingKey {
            case message, error, done
            case doneReason = "done_reason"
            case promptTokens = "prompt_eval_count"
        }
    }
}
