import SwiftUI

// MARK: - SettingsView

@available(macOS 13.0, *)
struct SettingsView: View {

    @AppStorage(AppSettings.Keys.openAIAPIKey) private var apiKey = ""
    @AppStorage(AppSettings.Keys.transcriptionLanguage) private var language = "en"
    @State private var apiKeyRevealed = false
    @State private var apiKeyTestResult: TestResult?
    @State private var isTesting = false

    enum TestResult {
        case success
        case failure(String)

        var color: Color {
            switch self { case .success: return .green; case .failure: return .red }
        }
        var message: String {
            switch self {
            case .success: return "✓ API key is valid"
            case .failure(let msg): return "✗ \(msg)"
            }
        }
    }

    private let languages: [(code: String, name: String)] = [
        ("", "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("ar", "Arabic"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // OpenAI API Key
                GroupBox("Transcription") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OpenAI API Key")
                                .font(.subheadline.weight(.medium))
                            Text("Used for Whisper transcription. Get yours at platform.openai.com")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Group {
                                if apiKeyRevealed {
                                    TextField("sk-...", text: $apiKey)
                                } else {
                                    SecureField("sk-...", text: $apiKey)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: apiKey) { _ in
                                apiKeyTestResult = nil
                            }

                            Button {
                                apiKeyRevealed.toggle()
                            } label: {
                                Image(systemName: apiKeyRevealed ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        HStack {
                            Button("Test Key") {
                                testAPIKey()
                            }
                            .disabled(apiKey.isEmpty || isTesting)
                            .buttonStyle(.bordered)

                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            }

                            if let result = apiKeyTestResult {
                                Text(result.message)
                                    .font(.caption)
                                    .foregroundStyle(result.color)
                            }

                            Spacer()
                        }

                        // Language picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Transcription Language")
                                .font(.subheadline.weight(.medium))
                            Text("Specifying the language improves accuracy. Auto-detect works but is slightly less accurate.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("", selection: $language) {
                                ForEach(languages, id: \.code) { lang in
                                    Text(lang.name).tag(lang.code)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 200)
                        }
                    }
                    .padding(4)
                }

                // About
                GroupBox("About") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Version").foregroundStyle(.secondary)
                            Spacer()
                            Text("0.1.0")
                        }
                        HStack {
                            Text("Transcription").foregroundStyle(.secondary)
                            Spacer()
                            Text("OpenAI Whisper API")
                        }
                        HStack {
                            Text("System Audio").foregroundStyle(.secondary)
                            Spacer()
                            Text("ScreenCaptureKit")
                        }
                        HStack {
                            Text("Database").foregroundStyle(.secondary)
                            Spacer()
                            Text(AppDatabase.databaseURL.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Divider()

                        Button("Open Database Location") {
                            NSWorkspace.shared.activateFileViewerSelecting([AppDatabase.databaseURL])
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                    }
                    .font(.subheadline)
                    .padding(4)
                }

                // Permissions status
                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: 8) {
                        PermissionRow(
                            icon: "mic.fill",
                            title: "Microphone",
                            description: "Captures your voice"
                        )
                        PermissionRow(
                            icon: "display",
                            title: "Screen Recording",
                            description: "Required for system audio capture"
                        )

                        Button("Open Privacy Settings") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                    }
                    .padding(4)
                }
            }
            .padding(16)
        }
        .frame(width: 380, height: 480)
    }

    private func testAPIKey() {
        isTesting = true
        apiKeyTestResult = nil
        Task {
            do {
                // Make a minimal API call to validate the key
                var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        await MainActor.run { apiKeyTestResult = .success; isTesting = false }
                    } else if http.statusCode == 401 {
                        await MainActor.run { apiKeyTestResult = .failure("Invalid API key"); isTesting = false }
                    } else {
                        await MainActor.run { apiKeyTestResult = .failure("HTTP \(http.statusCode)"); isTesting = false }
                    }
                }
            } catch {
                await MainActor.run { apiKeyTestResult = .failure(error.localizedDescription); isTesting = false }
            }
        }
    }
}

// MARK: - PermissionRow

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
