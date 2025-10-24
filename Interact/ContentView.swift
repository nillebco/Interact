import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authManager: AuthorizationManager
    @StateObject private var viewModel = WindowInteractionViewModel()
    @StateObject private var aiSettingsViewModel: AISettingsViewModel
    @State private var isShowingSettings = false

    init() {
        _aiSettingsViewModel = StateObject(wrappedValue: AISettingsViewModel(service: AIService()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            permissionStatusBar

            HStack(spacing: 16) {
                windowList
                    .frame(width: 260)

                Divider()

                interactionPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.refreshWindows()
        }
        .sheet(isPresented: $isShowingSettings) {
            AISettingsView(viewModel: aiSettingsViewModel) {
                isShowingSettings = false
            }
        }
        .alert("Action Failed", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            if let error = viewModel.lastError {
                Text(error)
            }
        }
    }

    private var permissionStatusBar: some View {
        HStack(spacing: 20) {
            permissionIndicator(
                granted: authManager.accessibilityAuthorized,
                title: "Accessibility",
                help: "Required to deliver keystrokes to other apps.",
                action: AuthorizationManager.shared.ensureAccessibilityPermission
            )

            permissionIndicator(
                granted: authManager.screenRecordingAuthorized,
                title: "Screen Recording",
                help: "Required to capture screenshots of other windows.",
                action: AuthorizationManager.shared.ensureScreenRecordingPermission
            )

            Spacer()

            Button {
                isShowingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)

            Button {
                AuthorizationManager.shared.refreshStatuses()
                viewModel.refreshWindows()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private func permissionIndicator(
        granted: Bool,
        title: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(granted ? "Granted" : "Needs approval")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(granted ? "Check again" : "Request") {
                action()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    AuthorizationManager.shared.refreshStatuses()
                }
            }
            .buttonStyle(.borderedProminent)
            .help(help)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var windowList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Visible Windows")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.refreshWindows()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload the on-screen windows list")
            }

            List(viewModel.windows, id: \.id) { window in
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.displayTitle)
                        .font(.body)
                    Text(window.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.selectedWindow?.id == window.id ? Color.accentColor.opacity(0.2) : .clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectedWindowID = window.id
                }
            }
            .listStyle(.plain)
        }
    }

    private var interactionPanel: some View {
        Group {
            if let window = viewModel.selectedWindow {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(window.displayTitle)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(window.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Frame: \(Int(window.bounds.width)) × \(Int(window.bounds.height))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    screenshotSection
                    Divider()
                    textSection
                    Divider()
                    shortcutSection

                    Spacer()
                }
            } else {
                VStack {
                    Spacer()
                    Text("Select a window from the list to get started.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Screenshot")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.captureScreenshot()
                } label: {
                    Label("Capture", systemImage: "camera")
                }
            }

            if let screenshot = viewModel.screenshot {
                Image(nsImage: screenshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 240)
                    .cornerRadius(8)
                    .shadow(radius: 4)

                Button {
                    viewModel.saveScreenshotToDesktop()
                } label: {
                    Label("Save to Desktop", systemImage: "square.and.arrow.down")
                }
            } else {
                Text("No screenshot captured yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send Text")
                .font(.headline)

            TextField(
                "Text to type in the target window",
                text: Binding(
                    get: { viewModel.textToSend },
                    set: { viewModel.textToSend = $0 }
                ),
                axis: .vertical
            )
            .lineLimit(3, reservesSpace: true)
            .textFieldStyle(.roundedBorder)
            .disableAutocorrection(true)

            Button {
                viewModel.sendText()
            } label: {
                Label("Send Text", systemImage: "text.insert")
            }
            .disabled(viewModel.textToSend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send Shortcut / Key Press")
                .font(.headline)

            HStack(spacing: 12) {
                TextField(
                    "Key or name (A, 1, return, space…)",
                    text: Binding(
                        get: { viewModel.shortcutInput.key },
                        set: { viewModel.shortcutInput.key = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

                modifierToggle("⌘", binding: Binding(
                    get: { viewModel.shortcutInput.useCommand },
                    set: { viewModel.shortcutInput.useCommand = $0 }
                ))

                modifierToggle("⌥", binding: Binding(
                    get: { viewModel.shortcutInput.useOption },
                    set: { viewModel.shortcutInput.useOption = $0 }
                ))

                modifierToggle("⌃", binding: Binding(
                    get: { viewModel.shortcutInput.useControl },
                    set: { viewModel.shortcutInput.useControl = $0 }
                ))

                modifierToggle("⇧", binding: Binding(
                    get: { viewModel.shortcutInput.useShift },
                    set: { viewModel.shortcutInput.useShift = $0 }
                ))
            }

            HStack {
                Button {
                    viewModel.sendShortcut()
                } label: {
                    Label("Send Shortcut", systemImage: "keyboard")
                }
                .disabled(viewModel.shortcutInput.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Clear") {
                    viewModel.shortcutInput.reset()
                }
                .buttonStyle(.borderless)

                Spacer()

                Text("Supported keys: letters, digits, arrows, function keys, return, tab, space, delete…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func modifierToggle(_ symbol: String, binding: Binding<Bool>) -> some View {
        Toggle(symbol, isOn: binding)
            .toggleStyle(.switch)
            .frame(width: 46)
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.lastError != nil },
            set: { newValue in
                if !newValue {
                    viewModel.clearError()
                }
            }
        )
    }
}
