import Foundation

// MARK: - WhisperService

/// Transcribes audio using the OpenAI Whisper API.
/// Uses the `whisper-1` model (large model) for maximum accuracy.
/// Audio is sent over HTTPS and is NOT stored by OpenAI beyond the API call.
final class WhisperService {

    // MARK: - Configuration

    struct Config {
        var apiKey: String
        /// Language hint — ISO 639-1 code. nil = auto-detect.
        /// Providing the correct language improves accuracy significantly.
        var language: String? = "en"
        /// Temperature: 0 = most deterministic/accurate, 1 = creative. Keep at 0 for meetings.
        var temperature: Double = 0
        /// Response format
        var responseFormat: ResponseFormat = .verboseJSON
    }

    enum ResponseFormat: String {
        case json
        case text
        case verboseJSON = "verbose_json"
        case srt
        case vtt
    }

    // MARK: - Types

    struct TranscriptionResult {
        let text: String
        let segments: [Segment]?
        let duration: Double?
        let language: String?

        struct Segment: Codable {
            let id: Int
            let start: Double
            let end: Double
            let text: String
            let noSpeechProb: Double?

            enum CodingKeys: String, CodingKey {
                case id, start, end, text
                case noSpeechProb = "no_speech_prob"
            }
        }
    }

    enum TranscriptionError: LocalizedError {
        case missingAPIKey
        case fileTooLarge(Int)
        case apiError(Int, String)
        case decodingError(String)
        case networkError(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "OpenAI API key not configured. Add it in Settings."
            case .fileTooLarge(let sizeMB):
                return "Audio file is \(sizeMB)MB. Whisper API limit is 25MB. Try a shorter recording."
            case .apiError(let code, let message):
                return "Whisper API error \(code): \(message)"
            case .decodingError(let msg):
                return "Failed to parse transcription response: \(msg)"
            case .networkError(let msg):
                return "Network error during transcription: \(msg)"
            }
        }
    }

    // MARK: - Transcription

    /// Transcribes an audio file using the Whisper API.
    /// - Parameter fileURL: Path to the audio file (WAV, MP3, M4A, etc.)
    /// - Parameter config: API configuration including the key and language hint
    /// - Returns: TranscriptionResult with the transcript text and optional segments
    static func transcribe(fileURL: URL, config: Config) async throws -> TranscriptionResult {
        guard !config.apiKey.isEmpty else {
            throw TranscriptionError.missingAPIKey
        }

        // Check file size (Whisper API limit: 25 MB)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        let maxSizeBytes = 25 * 1024 * 1024
        if fileSize > maxSizeBytes {
            throw TranscriptionError.fileTooLarge(fileSize / 1024 / 1024)
        }

        // Build multipart form request
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300 // 5 min timeout for long meetings

        let audioData: Data
        do {
            audioData = try Data(contentsOf: fileURL)
        } catch {
            throw TranscriptionError.networkError("Failed to read audio file: \(error.localizedDescription)")
        }

        let body = buildMultipartBody(
            boundary: boundary,
            audioData: audioData,
            filename: fileURL.lastPathComponent,
            model: "whisper-1",
            language: config.language,
            temperature: config.temperature,
            responseFormat: config.responseFormat.rawValue,
            prompt: "This is a meeting recording. Please transcribe accurately including all participants."
        )
        request.httpBody = body

        // Execute request
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranscriptionError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = parseErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            throw TranscriptionError.apiError(httpResponse.statusCode, errorMessage)
        }

        // Parse response
        return try parseResponse(data: data, format: config.responseFormat)
    }

    // MARK: - Request Building

    private static func buildMultipartBody(
        boundary: String,
        audioData: Data,
        filename: String,
        model: String,
        language: String?,
        temperature: Double,
        responseFormat: String,
        prompt: String?
    ) -> Data {
        var body = Data()

        func appendField(_ name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // Audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        appendField("model", value: model)
        appendField("response_format", value: responseFormat)
        appendField("temperature", value: String(temperature))

        if let language {
            appendField("language", value: language)
        }

        if let prompt {
            appendField("prompt", value: prompt)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    // MARK: - Response Parsing

    private static func parseResponse(data: Data, format: ResponseFormat) throws -> TranscriptionResult {
        switch format {
        case .text:
            guard let text = String(data: data, encoding: .utf8) else {
                throw TranscriptionError.decodingError("Could not decode text response")
            }
            return TranscriptionResult(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                       segments: nil, duration: nil, language: nil)

        case .json:
            struct SimpleResponse: Decodable { let text: String }
            do {
                let parsed = try JSONDecoder().decode(SimpleResponse.self, from: data)
                return TranscriptionResult(text: parsed.text, segments: nil, duration: nil, language: nil)
            } catch {
                throw TranscriptionError.decodingError(error.localizedDescription)
            }

        case .verboseJSON:
            struct VerboseResponse: Decodable {
                let text: String
                let language: String?
                let duration: Double?
                let segments: [TranscriptionResult.Segment]?
            }
            do {
                let decoder = JSONDecoder()
                let parsed = try decoder.decode(VerboseResponse.self, from: data)
                let cleanText = formatTranscript(text: parsed.text, segments: parsed.segments)
                return TranscriptionResult(
                    text: cleanText,
                    segments: parsed.segments,
                    duration: parsed.duration,
                    language: parsed.language
                )
            } catch {
                throw TranscriptionError.decodingError(error.localizedDescription)
            }

        case .srt, .vtt:
            guard let text = String(data: data, encoding: .utf8) else {
                throw TranscriptionError.decodingError("Could not decode subtitle response")
            }
            return TranscriptionResult(text: text, segments: nil, duration: nil, language: nil)
        }
    }

    /// Post-processes the raw Whisper output for readability.
    private static func formatTranscript(text: String, segments: [TranscriptionResult.Segment]?) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // If we have segments, filter out high no-speech probability segments
        // (hallucinations from silence/background noise)
        if let segments {
            let cleanSegments = segments.filter { segment in
                let noSpeechProb = segment.noSpeechProb ?? 0
                return noSpeechProb < 0.6 // Filter likely hallucinations
            }
            if !cleanSegments.isEmpty {
                result = cleanSegments
                    .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .joined(separator: " ")
            }
        }

        return result
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        struct ErrorResponse: Decodable {
            struct ErrorDetail: Decodable {
                let message: String
            }
            let error: ErrorDetail
        }
        return (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
    }
}

// MARK: - Settings Integration

extension WhisperService {
    /// Convenience: reads API key from UserDefaults.
    static var defaultConfig: Config {
        let key = UserDefaults.standard.string(forKey: AppSettings.Keys.openAIAPIKey) ?? ""
        let lang = UserDefaults.standard.string(forKey: AppSettings.Keys.transcriptionLanguage) ?? "en"
        return Config(apiKey: key, language: lang.isEmpty ? nil : lang)
    }
}
