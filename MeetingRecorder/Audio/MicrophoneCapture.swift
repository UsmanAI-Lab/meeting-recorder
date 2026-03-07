import Foundation
import AVFoundation

// MARK: - MicrophoneCapture

/// Captures microphone audio using AVAudioEngine.
/// Delivers PCM buffers to the provided handler for mixing.
final class MicrophoneCapture {

    // MARK: - Properties

    private let engine = AVAudioEngine()
    private(set) var isCapturing = false

    /// Called on every captured PCM buffer. May be called on any thread.
    var onBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    /// The format produced by the mic tap (matches engine's input format).
    private(set) var outputFormat: AVAudioFormat?

    // MARK: - Start

    func startCapture() throws {
        guard !isCapturing else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Prefer a standard format for easier mixing: 44100 Hz, stereo, float32
        let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: min(inputFormat.channelCount, 2),
            interleaved: false
        ) ?? inputFormat

        outputFormat = tapFormat

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, time in
            self?.onBuffer?(buffer, time)
        }

        try engine.start()
        isCapturing = true
    }

    // MARK: - Stop

    func stopCapture() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        outputFormat = nil
    }

    // MARK: - Permission Check

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
