import SwiftUI

struct AISettingsView: View {
    @ObservedObject var viewModel: AISettingsViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()
            content
            statusSection
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            viewModel.load()
        }
    }

    private var header: some View {
        HStack {
            Text("AI Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button("Close") {
                onClose()
            }
            .buttonStyle(.bordered)
        }
    }

    private var content: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $viewModel.provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.provider) { newValue in
                    viewModel.updateProvider(newValue)
                }
            }

        if viewModel.provider == .ollama {
            ollamaSection
        } else {
            openAISection
        }

        modelsSection
        promptSection
        actionsSection
        }
        .formStyle(.grouped)
    }

    private var ollamaSection: some View {
        Section("Ollama Configuration") {
            TextField("Host", text: $viewModel.ollamaHost)
            TextField("Port", text: $viewModel.ollamaPort)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var openAISection: some View {
        Section("OpenAI Configuration") {
            TextField("Endpoint", text: $viewModel.openAIEndpoint)
            SecureField("API Key", text: $viewModel.openAIApiKey)
        }
    }

    private var modelsSection: some View {
        Section("Model Selection") {
            if viewModel.isLoadingModels {
                ProgressView()
            } else {
                Picker("Model", selection: Binding(
                    get: { viewModel.selectedModelID ?? "" },
                    set: { newValue in
                        viewModel.selectModel(newValue.isEmpty ? nil : newValue)
                    }
                )) {
                    Text("Auto-select").tag("")
                    ForEach(viewModel.availableModels) { model in
                        Text(model.name).tag(model.id)
                    }
                }
            }

            Button("Refresh Models") {
                Task {
                    await viewModel.handleRefreshTapped()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var promptSection: some View {
        Section("Assistant Prompt") {
            TextEditor(text: $viewModel.prompt)
                .frame(minHeight: 160)
                .font(.body)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                )

            Text("Defines how the assistant should behave when operating apps on your behalf.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionsSection: some View {
        Section {
            HStack {
                Button(viewModel.isTestingConnection ? "Testing..." : "Test Connection") {
                    Task { await viewModel.testConnection() }
                }
                .disabled(viewModel.isTestingConnection)

                Spacer()

                Button("Save Changes") {
                    Task { await viewModel.saveChanges() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let status = viewModel.statusMessage {
                Label(status, systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            }

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
struct AISettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AISettingsView(viewModel: AISettingsViewModel(service: AIService()), onClose: {})
    }
}
#endif
