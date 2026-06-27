import Foundation
import Speech

final class SpeechService {
    private let recognizer: SFSpeechRecognizer

    enum SpeechError: Error, LocalizedError {
        case notAuthorized
        case recognizerUnavailable
        case transcriptionFailed

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Accès à la reconnaissance vocale refusé"
            case .recognizerUnavailable: return "Reconnaissance vocale indisponible"
            case .transcriptionFailed: return "La transcription a échoué"
            }
        }
    }

    init() throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR")) else {
            throw SpeechError.recognizerUnavailable
        }
        recognizer.supportsOnDeviceRecognition = true
        self.recognizer = recognizer
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw SpeechError.notAuthorized
        }

        guard recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = false
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal else { return }

                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }
}
