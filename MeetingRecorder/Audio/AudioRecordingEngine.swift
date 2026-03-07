import Foundation
import AVFoundation

// MARK: - RecordingState

enum RecordingState: Equatable {
    case idle
    case recording(startTime: Date)
    case processing   // transcription in flight
}

// MARK: - RecordingError

enum RecordingError: LocalizedError {
    case microphonePermissionDenied
    case screenRecordingPermissionDenied
    case fileWriteFailure(String)
    case alreadyRecording

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access denied. Please enable it in System Settings → Privacy & Security → Microphone."
        case .screenRecordingPermissionDenied:
            return "Screen Recording access denied. Required for system audio capture. Enable in System Settings → Privacy & Security → Screen Recording."
        case .fileWriteFailure(let msg):
            return "Failed to write audio file: \(msg)"
        case .alreadyRecording:
            return "Already recording."
        }
    }
}

// MARK: - AudioRecordingEngine

/// Orchestrates microphone + system audio capture into a single mixed audio file.
/// The file is written to a temp location and returned on stop for transcription.
@available(macOS 13.0, *)
@MainActor
final class AudioRecordingEngine: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var lastError: String?

    // MARK: - Private Components

    private let micCapture = MicrophoneCapture()
    private let systemCapture = SystemAudioCapture()

    private var audioFile: AVAudioFile?
    private var audioFilePath: URL?
    private var mixer: AVAudioMixerNode?
    private var durationTimer: Timer?

    // Internal state
    private var recordingStartTime: Date?

    // MARK: - Constants

    /// Common recording format: 44100 Hz, stereo, float32
    private let recordingFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 44100,
        channels: 2,
        interleaved: false
    )!

    // MARK: - Start Recording

    func startRecording() async throws {
        guard case .idle = state else { throw RecordingError.alreadyRecording }

        // Check permissions
        let micGranted = await MicrophoneCapture.requestPermission()
        guard micGranted else { throw RecordingError.microphonePermissionDenied }

        let screenGranted = await SystemAudioCapture.checkPermission()
        guard screenGranted else { throw RecordingError.screenRecordingPermissionDenied }

        // Set up temp audio file
        let tempURL = makeTempAudioURL()
        do {
            audioFile = try AVAudioFile(
                forWriting: tempURL,
                settings: recordingFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw RecordingError.fileWriteFailure(error.localizedDescription)
        }
        audioFilePath = tempURL

        // Start microphone capture
        try micCapture.startCapture()
        micCapture.onBuffer = { [weak self] buffer, _ in
            self?.writeBuffer(buffer, source: .microphone)
        }

        // Start system audio capture
        try await systemCapture.startCapture()
        systemCapture.onBuffer = { [weak self] buffer, _ in
            self?.writeBuffer(buffer, source: .system)
        }

        // Update state
        recordingStartTime = Date()
        state = .recording(startTime: recordingStartTime!)
        lastError = nil

        // Start duration timer on main thread
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            Task { @MainActor in
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }

        print("[AudioRecordingEngine] Recording started → \(tempURL.lastPathComponent)")
    }

    // MARK: - Stop Recording

    /// Stops recording and returns the audio file URL + duration.
    /// Caller is responsible for deleting the file after transcription.
    func stopRecording() async -> (url: URL, duration: TimeInterval)? {
        guard case .recording = state else { return nil }

        // Stop captures
        micCapture.stopCapture()
        await systemCapture.stopCapture()

        // Stop timer
        durationTimer?.invalidate()
        durationTimer = nil

        let duration = recordingDuration

        // Close audio file
        let fileURL = audioFilePath
        audioFile = nil
        audioFilePath = nil
        recordingDuration = 0
        recordingStartTime = nil

        state = .processing

        guard let url = fileURL else {
            state = .idle
            return nil
        }

        print("[AudioRecordingEngine] Recording stopped. Duration: \(Int(duration))s → \(url.lastPathComponent)")
        return (url: url, duration: duration)
    }

    /// Call this when processing is complete (transcription done or failed).
    func finishProcessing() {
        state = .idle
    }

    // MARK: - Buffer Writing

    private let writeLock = NSLock()

    private enum AudioSource { case microphone, system }

    /// Writes a PCM buffer to the audio file, resampling/reformatting as needed.
    private func writeBuffer(_ buffer: AVAudioPCMBuffer, source: AudioSource) {
        guard let file = audioFile else { return }

        writeLock.lock()
        defer { writeLock.unlock() }

        do {
            // If format matches, write directly
            if buffer.format == recordingFormat {
                try file.write(from: buffer)
                return
            }

            // Convert buffer format to our recording format
            guard let converter = AVAudioConverter(from: buffer.format, to: recordingFormat) else {
                return
            }

            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * recordingFormat.sampleRate / buffer.format.sampleRate
            )

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: recordingFormat,
                frameCapacity: frameCapacity + 1
            ) else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

            if let error {
                print("[AudioRecordingEngine] Conversion error (\(source)): \(error)")
                return
            }

            try file.write(from: convertedBuffer)
        } catch {
            print("[AudioRecordingEngine] Write error (\(source)): \(error)")
        }
    }

    // MARK: - Helpers

    private func makeTempAudioURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "meeting-\(Int(Date().timeIntervalSince1970)).wav"
        return tempDir.appendingPathComponent(filename)
    }

    // MARK: - Formatting

    var formattedDuration: String {
        let total = Int(recordingDuration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}
