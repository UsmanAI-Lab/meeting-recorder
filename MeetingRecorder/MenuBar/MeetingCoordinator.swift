import Foundation
import SwiftUI

// MARK: - MeetingCoordinator

/// The central coordinator that connects recording → transcription → database.
/// This is the single ObservableObject shared across all views.
@available(macOS 13.0, *)
@MainActor
final class MeetingCoordinator: ObservableObject {

    // MARK: - Published State

    @Published private(set) var recordingState: RecordingState = .idle
    @Published private(set) var meetings: [Meeting] = []
    @Published private(set) var isTranscribing = false
    @Published var alertMessage: String?
    @Published var showAlert = false

    // MARK: - Dependencies

    let engine: AudioRecordingEngine
    private let db: AppDatabase

    // MARK: - Init

    init() {
        self.engine = AudioRecordingEngine()
        self.db = AppDatabase.shared
        loadMeetings()
    }

    // MARK: - Recording Control

    func startRecording() {
        Task {
            do {
                try await engine.startRecording()
                recordingState = engine.state
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    func stopRecording() {
        Task {
            guard let result = await engine.stopRecording() else {
                engine.finishProcessing()
                return
            }

            recordingState = engine.state  // .processing
            isTranscribing = true

            let audioURL = result.url
            let duration = result.duration
            let recordingDate = Date()

            // Transcribe
            do {
                let config = WhisperService.defaultConfig

                guard !config.apiKey.isEmpty else {
                    showError("OpenAI API key not set. Add it in Settings before recording.")
                    cleanupAudio(at: audioURL)
                    engine.finishProcessing()
                    isTranscribing = false
                    return
                }

                let transcription = try await WhisperService.transcribe(fileURL: audioURL, config: config)

                // Save to database
                var meeting = Meeting(
                    title: Meeting.defaultTitle(for: recordingDate),
                    date: recordingDate,
                    duration: duration,
                    transcript: transcription.text,
                    rawTranscript: transcription.text
                )
                try db.saveMeeting(&meeting)

                // Delete audio file
                cleanupAudio(at: audioURL)

                // Reload meetings
                loadMeetings()

                isTranscribing = false
                engine.finishProcessing()
                recordingState = .idle

                print("[MeetingCoordinator] Meeting saved: \(meeting.title)")

            } catch {
                cleanupAudio(at: audioURL)
                engine.finishProcessing()
                isTranscribing = false
                recordingState = .idle
                showError("Transcription failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Data Operations

    func loadMeetings() {
        do {
            meetings = try db.fetchAllMeetings()
        } catch {
            print("[MeetingCoordinator] Failed to load meetings: \(error)")
        }
    }

    func deleteMeeting(_ meeting: Meeting) {
        guard let id = meeting.id else { return }
        do {
            try db.deleteMeeting(id: id)
            loadMeetings()
        } catch {
            showError("Failed to delete meeting: \(error.localizedDescription)")
        }
    }

    func renameMeeting(_ meeting: Meeting, title: String) {
        guard let id = meeting.id else { return }
        do {
            try db.renameMeeting(id: id, title: title)
            loadMeetings()
        } catch {
            showError("Failed to rename meeting: \(error.localizedDescription)")
        }
    }

    func searchMeetings(query: String) -> [Meeting] {
        if query.isEmpty { return meetings }
        do {
            return try db.searchMeetings(query: query)
        } catch {
            return meetings.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.transcript.localizedCaseInsensitiveContains(query)
            }
        }
    }

    // MARK: - Computed Properties

    var isRecording: Bool {
        if case .recording = recordingState { return true }
        return false
    }

    var isBusy: Bool {
        isRecording || isTranscribing
    }

    var statusLabel: String {
        switch recordingState {
        case .idle:
            return isTranscribing ? "Transcribing…" : "Ready"
        case .recording:
            return "Recording \(engine.formattedDuration)"
        case .processing:
            return "Transcribing…"
        }
    }

    // MARK: - Helpers

    private func cleanupAudio(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            print("[MeetingCoordinator] Deleted audio file: \(url.lastPathComponent)")
        } catch {
            print("[MeetingCoordinator] Failed to delete audio: \(error)")
        }
    }

    private func showError(_ message: String) {
        alertMessage = message
        showAlert = true
        print("[MeetingCoordinator] Error: \(message)")
    }
}
