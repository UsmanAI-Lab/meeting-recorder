import Foundation
import AVFoundation
import ScreenCaptureKit
import Darwin

// MARK: - SystemAudioCapture

/// Captures system audio (all app output) using ScreenCaptureKit.
/// No screen content is captured — audio only.
/// Requires Screen Recording permission (needed even for audio-only capture).
@available(macOS 13.0, *)
final class SystemAudioCapture: NSObject {

    // MARK: - Properties

    private var stream: SCStream?
    private(set) var isCapturing = false

    /// Called on every system audio PCM buffer. May be called on any thread.
    var onBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    private let sampleRate: Double = 44100.0
    private let channelCount: UInt32 = 2

    private(set) var outputFormat: AVAudioFormat?

    // MARK: - Start

    func startCapture() async throws {
        guard !isCapturing else { return }

        // Get available content (we only need a display reference to create the filter)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw CaptureError.noDisplayFound
        }

        // Configure for audio-only capture (minimal video dimensions)
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = Int(sampleRate)
        config.channelCount = Int(channelCount)
        // Minimal video to satisfy SCStream requirements; we discard video frames
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps max

        // Exclude no apps — we want all system audio
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let outputQueue = DispatchQueue(label: "com.usmanailab.MeetingRecorder.systemAudio", qos: .userInteractive)
        stream = SCStream(filter: filter, configuration: config, delegate: nil)

        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
        try await stream?.startCapture()

        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )

        isCapturing = true
    }

    // MARK: - Stop

    func stopCapture() async {
        guard isCapturing else { return }
        try? await stream?.stopCapture()
        stream = nil
        isCapturing = false
        outputFormat = nil
    }

    // MARK: - Permission Check

    static func checkPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Error Types

    enum CaptureError: LocalizedError {
        case noDisplayFound
        case streamFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDisplayFound:
                return "No display found for system audio capture."
            case .streamFailed(let msg):
                return "Stream failed: \(msg)"
            }
        }
    }
}

// MARK: - SCStreamOutput

@available(macOS 13.0, *)
extension SystemAudioCapture: SCStreamOutput {

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        do {
            guard let pcmBuffer = try sampleBuffer.asPCMBuffer() else { return }
            let time = AVAudioTime(hostTime: mach_absolute_time())
            onBuffer?(pcmBuffer, time)
        } catch {
            // Non-fatal: log and continue
            print("[SystemAudioCapture] Buffer conversion error: \(error)")
        }
    }
}

// MARK: - CMSampleBuffer Extension

extension CMSampleBuffer {
    /// Converts a CMSampleBuffer (from ScreenCaptureKit audio) to AVAudioPCMBuffer.
    func asPCMBuffer() throws -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self) else { return nil }

        guard let streamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        guard let audioFormat = AVAudioFormat(streamDescription: streamBasicDescription) else { return nil }

        let frameCount = UInt32(CMSampleBufferGetNumSamples(self))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else { return nil }
        pcmBuffer.frameLength = frameCount

        let audioBufferList = pcmBuffer.mutableAudioBufferList
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(self, at: 0, frameCount: Int32(frameCount), into: audioBufferList) == noErr else {
            return nil
        }

        return pcmBuffer
    }
}
