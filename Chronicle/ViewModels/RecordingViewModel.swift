import Foundation
import SwiftUI
import CoreData

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var transcription: String = ""
    @Published var correctedTranscription: String = ""
    @Published var taggedText: TaggedText?
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
    private var gliner = GLiNERService()
    private var toolExecutor: ToolExecutor?
    private var preProcessor: PreProcessor?
    private var viewContext: NSManagedObjectContext?

    func setup(context: NSManagedObjectContext, llmService: LLMService) {
        self.viewContext = context
        self.llm = llmService
        self.toolExecutor = ToolExecutor(context: context)
        self.preProcessor = PreProcessor(context: context)
        self.speech = SpeechService()
        recorder.prepareSession()

        Task.detached(priority: .background) {
            do {
                try await self.gliner.load()
            } catch {
                print("⚠️ GLiNER: \(error)")
            }
        }

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

                // Étape 2 : Sauvegarder l'entrée
                let entry = try saveEntry(
                    audioURL: audioURL,
                    rawTranscription: rawText,
                    correctedTranscription: nil
                )

                // Étape 3 : GLiNER NER (zero-shot, on-device)
                state = .processing
                llmStatus = "Extraction des entités…"

                let glinerEntities = try gliner.extractEntities(from: rawText)

                // Convertir GLiNER entities en DetectedEntity
                let detected: [DetectedEntity] = glinerEntities.compactMap { entity in
                    let startIdx = rawText.index(rawText.startIndex, offsetBy: entity.startIdx, limitedBy: rawText.endIndex) ?? rawText.startIndex
                    let endIdx = rawText.index(rawText.startIndex, offsetBy: entity.endIdx, limitedBy: rawText.endIndex) ?? rawText.endIndex

                    let type: DetectedEntity.EntityType = switch entity.label {
                    case "person": .person
                    case "location": .place
                    case "event": .event
                    case "activity": .activity
                    default: .organization
                    }

                    return DetectedEntity(text: entity.text, type: type, range: startIdx..<endIdx)
                }

                // Fusionner avec NLTagger
                let nlpEntities = nlpService.detectEntities(in: rawText)
                var merged = detected
                for nlpEntity in nlpEntities {
                    let overlaps = merged.contains { $0.range.overlaps(nlpEntity.range) }
                    if !overlaps {
                        merged.append(nlpEntity)
                    }
                }
                merged.sort { $0.range.lowerBound < $1.range.lowerBound }

                // Appliquer les corrections utilisateur sur les entités détectées
                merged = merged.map { entity in
                    if let corrected = CorrectionStore.shared.correctedName(for: entity.text) {
                        print("🔄 Auto-correction: \(entity.text) → \(corrected)")
                        return DetectedEntity(text: corrected, type: entity.type, range: entity.range)
                    }
                    return entity
                }

                print("🏷️ Entités fusionnées: \(merged.map { "[\($0.type.rawValue):\($0.text)]" })")

                // Créer les entités CoreData
                let existing = preProcessor?.process(rawText: rawText).existingEntityNames ?? []
                if let toolExecutor {
                    try toolExecutor.createEntitiesFromNLP(
                        detected: merged,
                        existing: existing,
                        for: entry
                    )
                }

                // Mettre à jour les tags
                taggedText = TaggedText(rawText: rawText, entities: merged)

                llmStatus = ""
                state = .done
            } catch {
                print("❌ Erreur pipeline: \(error)")
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
        taggedText = nil
        elapsedTime = 0
        audioLevels = Array(repeating: 0, count: 40)
        llmStatus = ""
    }

    private let nlpService = NLPService()

    private func updateTaggedText(from text: String) {
        let entities = nlpService.detectEntities(in: text)
        taggedText = TaggedText(rawText: text, entities: entities)
    }

    func handleTagEdit(segment: TaggedSegment, newText: String, newType: DetectedEntity.EntityType?) {
        guard let viewContext else { return }

        // Si le texte a changé, stocker la correction et mettre à jour CoreData
        if newText != segment.text, let type = newType {
            CorrectionStore.shared.addCorrection(from: segment.text, to: newText)
            switch type {
            case .place:
                // Renommer le lieu existant ou créer un nouveau
                let request = Lieu.fetchRequest()
                request.predicate = NSPredicate(format: "nom ==[cd] %@", segment.text)
                if let existing = try? viewContext.fetch(request).first {
                    existing.nom = newText
                } else {
                    let lieu = Lieu(context: viewContext)
                    lieu.id = UUID()
                    lieu.nom = newText
                    lieu.frequence = 1
                }
            case .person:
                let request = Personne.fetchRequest()
                request.predicate = NSPredicate(format: "nom ==[cd] %@", segment.text)
                if let existing = try? viewContext.fetch(request).first {
                    existing.nom = newText
                } else {
                    let person = Personne(context: viewContext)
                    person.id = UUID()
                    person.nom = newText
                    person.frequenceMention = 1
                }
            case .organization, .event, .activity:
                break
            }
            try? viewContext.save()
            print("✏️ Tag modifié: \(segment.text) → \(newText) [\(type.rawValue)]")
        }

        // Re-générer les tags avec le texte mis à jour
        if let tagged = taggedText {
            let updatedText = tagged.rawText.replacingOccurrences(of: segment.text, with: newText)
            correctedTranscription = updatedText
            updateTaggedText(from: updatedText)
        }
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
