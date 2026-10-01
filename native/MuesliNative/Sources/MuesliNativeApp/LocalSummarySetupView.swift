import SwiftUI
import MuesliCore

struct LocalSummarySetupView: View {
    let address: String
    let model: String
    @State private var isReady = false
    @State private var isBusy = false
    @State private var isChecking = true
    @State private var error: String?
    @State private var needsInstallation = false
    @State private var setupTask: Task<Void, Never>?

    private var selectedModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? LocalOllamaService.defaultModel : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isChecking {
                ProgressView("Checking local summaries…").controlSize(.small)
            } else if isReady {
                Label("\(selectedModel) is ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(MuesliTheme.success)
            } else {
                Button("Set up local summaries") {
                    isBusy = true
                    error = nil
                    needsInstallation = false
                    setupTask = Task {
                        defer { isBusy = false }
                        do {
                            let url = try LocalOllamaService.baseURL(address)
                            try await LocalOllamaService.shared.ensureReady(at: url, model: selectedModel, downloadMissing: true)
                            try Task.checkCancellation()
                            isReady = true
                        } catch is CancellationError {
                        } catch {
                            self.error = error.localizedDescription
                            if case .notInstalled? = error as? LocalOllamaError { needsInstallation = true }
                        }
                    }
                }
                .disabled(isBusy)
                .accessibilityIdentifier("summary.local.setup")
                if isBusy {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Preparing \(selectedModel)…")
                        Button("Cancel") { setupTask?.cancel() }
                    }
                } else {
                    Text("Downloads this model once if needed. The first download can use several GB.")
                        .foregroundStyle(MuesliTheme.textSecondary)
                }
            }
            Text((try? LocalOllamaService.baseURL(address)).map(LocalOllamaService.canStartLocalApp) == true
                 ? "Muesli remembers your model and starts local Ollama when you create notes."
                 : "Muesli remembers this server and model for future meeting notes.")
                .foregroundStyle(MuesliTheme.textSecondary)
            if let error {
                Text(error).foregroundStyle(.red)
                if needsInstallation {
                    Link("Download Ollama", destination: URL(string: "https://ollama.com/download/mac")!)
                }
            }
        }
        .font(MuesliTheme.caption())
        .task(id: address + "|" + model) {
            setupTask?.cancel()
            isChecking = true
            defer { isChecking = false }
            isReady = false
            error = nil
            needsInstallation = false
            do {
                let url = try LocalOllamaService.baseURL(address)
                try await LocalOllamaService.shared.ensureReady(at: url, model: selectedModel)
                try Task.checkCancellation()
                isReady = true
            } catch is CancellationError {
            } catch {
                if case .missingModel? = error as? LocalOllamaError { return }
                self.error = error.localizedDescription
                if case .notInstalled? = error as? LocalOllamaError { needsInstallation = true }
            }
        }
        .onDisappear { setupTask?.cancel() }
    }
}
