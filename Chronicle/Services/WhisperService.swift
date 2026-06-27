import Foundation

final class WhisperService {
    private var context: OpaquePointer?

    enum WhisperError: Error {
        case modelNotFound
        case initFailed
        case transcriptionFailed
    }

    init(modelName: String = "ggml-small") throws {
        guard let modelPath = Bundle.main.path(forResource: modelName, ofType: "bin") else {
            throw WhisperError.modelNotFound
        }

        var params = whisper_context_default_params()
        params.use_gpu = true

        guard let ctx = whisper_init_from_file_with_params(modelPath, params) else {
            throw WhisperError.initFailed
        }
        self.context = ctx
    }

    deinit {
        if let context {
            whisper_free(context)
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let context else { throw WhisperError.initFailed }

        let samples = try loadAudioSamples(url: audioURL)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                params.language = "fr".withCString { strdup($0) }
                params.n_threads = 4
                params.print_progress = false
                params.print_timestamps = false

                let result = samples.withUnsafeBufferPointer { buffer in
                    whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
                }

                if result != 0 {
                    continuation.resume(throwing: WhisperError.transcriptionFailed)
                    return
                }

                let segmentCount = whisper_full_n_segments(context)
                var text = ""
                for i in 0..<segmentCount {
                    if let cStr = whisper_full_get_segment_text(context, i) {
                        text += String(cString: cStr)
                    }
                }

                continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private func loadAudioSamples(url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        // WAV 16-bit PCM 16kHz mono — skip 44 byte header
        let rawData = data.dropFirst(44)
        let sampleCount = rawData.count / 2

        var samples = [Float](repeating: 0, count: sampleCount)
        rawData.withUnsafeBytes { buffer in
            let int16Ptr = buffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                samples[i] = Float(int16Ptr[i]) / 32768.0
            }
        }
        return samples
    }
}
