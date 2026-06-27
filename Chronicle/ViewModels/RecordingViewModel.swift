import Foundation
import SwiftUI
import CoreData

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var transcription: String = ""
    @Published var correctedTranscription: String = ""
    @Published var elapsedTime: TimeInterval = 0
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 40)
    @Published var llmStatus: String = ""

    enum RecordingState: Equatable {
        case idle
        case recording
        case transcribing
        case processing
        case done
        case error(String)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.recording, .recording),
                 (.transcribing, .transcribing), (.processing, .processing),
                 (.done, .done):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    let recorder = AudioRecorderService()
    private var speech: SpeechService?
    private var llm: LLMService?
    private var toolExecutor: ToolExecutor?
    private var viewContext: NSManagedObjectContext?

    func setup(context: NSManagedObjectContext, llmService: LLMService) {
        self.viewContext = context
        self.llm = llmService
        self.toolExecutor = ToolExecutor(context: context)
        self.speech = SpeechService()

        Task {
            guard let speech else { return }
            let authorized = await speech.requestAuthorization()
            if !authorized {
                state = .error("Accès à la reconnaissance vocale refusé")
                return
            }
            do {
                try await speech.ensureModelReady()
            } catch {
                print("⚠️ Modèle speech: \(error)")
            }
        }
    }

    func toggleRecording() {
        if recorder.isRecording {
            stopAndProcess()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        do {
            try recorder.startRecording()
            state = .recording
            observeRecorder()
        } catch {
            state = .error("Erreur micro : \(error.localizedDescription)")
        }
    }

    private func observeRecorder() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in
                self.elapsedTime = self.recorder.elapsedTime
                self.audioLevels = self.recorder.audioLevels
                if !self.recorder.isRecording && self.state == .recording {
                    timer.invalidate()
                    self.stopAndProcess()
                }
            }
        }
    }

    private func stopAndProcess() {
        guard let audioURL = recorder.currentFileURL else { return }
        recorder.stopRecording()
        state = .transcribing
        llmStatus = "Transcription en cours…"

        Task {
            do {
                try await Task.sleep(for: .milliseconds(800))

                // Debug : vérifier le fichier audio
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
                print("🎙️ Fichier audio: \(audioURL.lastPathComponent) — \(fileSize / 1024) KB — durée enregistrée: \(String(format: "%.1f", elapsedTime))s")

                // Étape 1 : Transcription Apple Speech
                guard let speech else { throw SpeechService.SpeechError.transcriptionFailed }
                let rawText = try await speech.transcribe(audioURL: audioURL)
                recorder.deactivateSession()
                transcription = rawText
                print("📝 Transcription brute: \(rawText)")

                // Étape 2 : Correction + extraction LLM
                if let llm, llm.isLoaded {
                    state = .processing
                    llmStatus = "Analyse et correction…"

                    let entities = toolExecutor?.fetchKnownEntities() ?? KnownEntities()
                    print("🧠 Entités connues: \(entities)")
                    let result = try await llm.processTranscription(rawText: rawText, knownEntities: entities)

                    correctedTranscription = result.correctedText
                    print("✅ Texte corrigé: \(result.correctedText)")
                    print("🔧 Tool calls: \(result.toolCalls.map { "\($0.name)(\($0.arguments))" })")

                    // Étape 3 : Sauvegarde CoreData
                    let entry = try saveEntry(
                        audioURL: audioURL,
                        rawTranscription: rawText,
                        correctedTranscription: result.correctedText
                    )

                    // Étape 4 : Exécution des tool calls
                    if let toolExecutor {
                        try toolExecutor.execute(toolCalls: result.toolCalls, for: entry)
                    }
                } else {
                    // LLM pas encore chargé — sauvegarde brute uniquement
                    _ = try saveEntry(audioURL: audioURL, rawTranscription: rawText, correctedTranscription: nil)
                }

                llmStatus = ""
                state = .done
            } catch {
                state = .error("Erreur : \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    private func saveEntry(audioURL: URL, rawTranscription: String, correctedTranscription: String?) throws -> EntreeVocale {
        guard let viewContext else { throw SpeechService.SpeechError.transcriptionFailed }
        let entry = EntreeVocale(context: viewContext)
        entry.id = UUID()
        entry.dateEnregistrement = Date()
        entry.dureeSecondes = elapsedTime
        entry.transcriptionBrute = rawTranscription
        entry.transcriptionCorrigee = correctedTranscription
        entry.cheminAudio = audioURL.lastPathComponent
        try viewContext.save()
        return entry
    }

    func reset() {
        state = .idle
        transcription = ""
        correctedTranscription = ""
        elapsedTime = 0
        audioLevels = Array(repeating: 0, count: 40)
        llmStatus = ""
    }

    var formattedTime: String {
        let mins = Int(elapsedTime) / 60
        let secs = Int(elapsedTime) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var remainingTime: String {
        let remaining = max(0, AudioRecorderService.maxDuration - elapsedTime)
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
