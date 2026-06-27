import Foundation
import Speech
import AVFoundation

final class SpeechService {
    private let locale = Locale(identifier: "fr-FR")

    enum SpeechError: Error, LocalizedError {
        case notAuthorized
        case transcriptionFailed
        case languageNotSupported

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Accès à la reconnaissance vocale refusé"
            case .transcriptionFailed: return "La transcription a échoué"
            case .languageNotSupported: return "Le français n'est pas supporté sur cet appareil"
            }
        }
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func ensureModelReady() async throws {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let status = await AssetInventory.status(forModules: [transcriber])

        if status == .installed {
            print("✅ Modèle de langue français déjà installé")
            return
        }

        print("📥 Téléchargement du modèle de langue française…")
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await downloader.downloadAndInstall()
        }
        print("✅ Modèle de langue prêt")
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw SpeechError.notAuthorized
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let audioFile = try AVAudioFile(forReading: audioURL)

        let analyzer = try await SpeechAnalyzer(
            inputAudioFile: audioFile,
            modules: [transcriber],
            finishAfterFile: true
        )

        var fullText = ""
        for try await segment in transcriber.results {
            if segment.isFinal {
                fullText += String(segment.text.characters)
            }
        }

        let result = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw SpeechError.transcriptionFailed }
        return result
    }
}
