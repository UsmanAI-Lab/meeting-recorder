import SwiftUI

// MARK: - MenuBarView

/// The main popover view shown when the user clicks the menu bar icon.
@available(macOS 13.0, *)
struct MenuBarView: View {

    @EnvironmentObject var coordinator: MeetingCoordinator
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var selectedTab: Tab = .meetings

    enum Tab { case meetings, settings }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            if selectedTab == .settings {
                SettingsView()
                    .frame(width: 380)
            } else {
                meetingsContent
            }
        }
        .frame(width: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Error", isPresented: $coordinator.showAlert) {
            Button("OK") { coordinator.showAlert = false }
        } message: {
            Text(coordinator.alertMessage ?? "An error occurred.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // App icon + title
            HStack(spacing: 8) {
                Image(systemName: coordinator.isRecording ? "waveform.circle.fill" : "waveform.circle")
                    .font(.title2)
                    .foregroundStyle(coordinator.isRecording ? .red : .blue)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Meeting Recorder")
                        .font(.headline)
                    Text(coordinator.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Record / Stop button
            recordButton

            // Settings toggle
            Button {
                selectedTab = selectedTab == .settings ? .meetings : .settings
            } label: {
                Image(systemName: selectedTab == .settings ? "xmark.circle.fill" : "gear")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")

            // Quit button
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit Meeting Recorder")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var recordButton: some View {
        Button {
            if coordinator.isRecording {
                coordinator.stopRecording()
            } else if !coordinator.isTranscribing {
                coordinator.startRecording()
            }
        } label: {
            HStack(spacing: 6) {
                if coordinator.isTranscribing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                    Text("Transcribing")
                } else if coordinator.isRecording {
                    Image(systemName: "stop.fill")
                    Text(coordinator.engine.formattedDuration)
                        .monospacedDigit()
                } else {
                    Image(systemName: "record.circle")
                    Text("Record")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                coordinator.isRecording ? Color.red : (coordinator.isTranscribing ? Color.orange : Color.blue),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(coordinator.isTranscribing)
        .animation(.easeInOut(duration: 0.2), value: coordinator.isRecording)
    }

    // MARK: - Meetings Content

    private var meetingsContent: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search transcripts…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Meeting list
            let filtered = coordinator.searchMeetings(query: searchText)

            if filtered.isEmpty {
                emptyState
            } else {
                TranscriptListView(meetings: filtered)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: coordinator.meetings.isEmpty ? "waveform.slash" : "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Group {
                if coordinator.meetings.isEmpty {
                    Text("No recordings yet\nClick Record to start")
                } else {
                    Text("No results for \"\(searchText)\"")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: 200)
    }
}

// MARK: - Preview

#if DEBUG
@available(macOS 13.0, *)
struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarView()
            .environmentObject(MeetingCoordinator())
    }
}
#endif
