import Foundation

extension AppConfig {
    var selectedLocalGemmaRuntime: LocalGemmaRuntime {
        LocalGemmaRuntime(rawValue: localGemmaRuntime) ?? .disabled
    }

    mutating func applyLocalGemmaPreset(_ runtime: LocalGemmaRuntime) {
        localGemmaRuntime = runtime.rawValue
        switch runtime {
        case .disabled:
            break
        case .ollama:
            meetingSummaryBackend = MeetingSummaryBackendOption.ollama.backend
            ollamaURL = "http://localhost:11434"
            ollamaModel = LocalGemmaRuntime.ollamaModel
        case .llamaCpp:
            meetingSummaryBackend = MeetingSummaryBackendOption.customLLM.backend
            customLLMFormat = CustomLLMFormat.openAI.rawValue
            customLLMURL = "http://127.0.0.1:8080/v1"
            customLLMAPIKey = ""
            customLLMModel = LocalGemmaRuntime.llamaCppModel
        }
    }
}
