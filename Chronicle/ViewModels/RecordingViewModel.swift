import Foundation
import SwiftUI
import CoreData

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var transcription: String = ""
    @Published var correctedTranscription: String = ""
    @Published var taggedText: TaggedText?
    @Published var lastRelations: [EntityRelation] = []
    @Published var elapsedTime: TimeInterval = 0
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 40)
    @Published var llmStatus: String = ""
    @Published var pipelineSteps: [PipelineStep] = []
    @Published var isVerifying: Bool = false
    @Published var isGeneratingSummary: Bool = false
    @Published var dailySummary: String = ""
    @Published var dailyTitle: String = ""

    struct PipelineStep: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        var status: StepStatus

        enum StepStatus {
            case pending, active, done, failed
        }
    }

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
    private let relationExtractor = RelationExtractor()
    private var toolExecutor: ToolExecutor?
    private var preProcessor: PreProcessor?
    private var viewContext: NSManagedObjectContext?

    private var isSetup = false

    func setup(context: NSManagedObjectContext, llmService: LLMService) {
        guard !isSetup else { return }
        isSetup = true

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
                AppLogger.log("⚠️ GLiNER: \(error)")
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
                AppLogger.log("⚠️ Modèle speech: \(error)")
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

    /// Annule l'enregistrement en cours (geste glisser à gauche) — pas de sauvegarde, pas de traitement
    func cancelRecording() {
        guard recorder.isRecording else { return }
        recorder.cancelRecording()
        elapsedTime = 0
        audioLevels = Array(repeating: 0, count: 40)
        state = .idle
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
        state = .processing

        pipelineSteps = [
            PipelineStep(icon: "waveform", label: "Transcription", status: .active),
            PipelineStep(icon: "tag", label: "Détection d'entités", status: .pending),
            PipelineStep(icon: "link", label: "Extraction de relations", status: .pending),
            PipelineStep(icon: "sparkles", label: "Vérification IA", status: .pending),
            PipelineStep(icon: "text.quote", label: "Résumé narratif", status: .pending),
        ]

        Task {
            do {
                // ── Étape 1 : Transcription ──
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
                AppLogger.log("🎙️ Fichier audio: \(audioURL.lastPathComponent) — \(fileSize / 1024) KB — durée enregistrée: \(String(format: "%.1f", elapsedTime))s")

                guard let speech else { throw SpeechService.SpeechError.transcriptionFailed }
                let rawText = try await speech.transcribe(audioURL: audioURL)
                recorder.deactivateSession()
                transcription = rawText
                AppLogger.log("📝 Transcription: \(rawText)")

                updateStep(0, status: .done)

                let entry = try saveEntry(
                    audioURL: audioURL,
                    rawTranscription: rawText,
                    correctedTranscription: nil
                )

                // ── Étape 2 : NER (GLiNER + NLTagger) ──
                updateStep(1, status: .active)

                if !gliner.isLoaded {
                    try await gliner.load()
                }
                let glinerEntities = try gliner.extractEntities(from: rawText)
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

                let nlpEntities = nlpService.detectEntities(in: rawText)
                var merged = detected
                for nlpEntity in nlpEntities {
                    if !merged.contains(where: { $0.range.overlaps(nlpEntity.range) }) {
                        merged.append(nlpEntity)
                    }
                }
                merged.sort { $0.range.lowerBound < $1.range.lowerBound }

                var seen = Set<String>()
                merged = merged.filter { entity in
                    let key = entity.text.lowercased()
                    if seen.contains(key) { return false }
                    seen.insert(key)
                    return true
                }

                merged = merged.map { entity in
                    if let corrected = CorrectionStore.shared.correctedName(for: entity.text) {
                        AppLogger.log("🔄 Auto-correction: \(entity.text) → \(corrected)")
                        return DetectedEntity(text: corrected, type: entity.type, range: entity.range)
                    }
                    return entity
                }

                AppLogger.log("🏷️ Entités fusionnées: \(merged.map { "[\($0.type.rawValue):\($0.text)]" })")

                let existing = preProcessor?.process(rawText: rawText).existingEntityNames ?? []
                if let toolExecutor {
                    try toolExecutor.createEntitiesFromNLP(
                        detected: merged.filter { $0.type == .person || $0.type == .place },
                        existing: existing,
                        for: entry
                    )
                }

                updateStep(1, status: .done)

                // ── Étape 3 : Relations ──
                updateStep(2, status: .active)

                let relations = relationExtractor.extractRelations(from: rawText, entities: merged)
                lastRelations = relations
                if let toolExecutor, !relations.isEmpty {
                    try toolExecutor.createStructuredEvents(from: relations, for: entry)
                }

                taggedText = TaggedText(rawText: rawText, entities: merged)

                updateStep(2, status: .done)

                // ── Étape 4 : Vérification IA ──
                updateStep(3, status: .active)

                // Libérer GLiNER (787MB) avant de charger le LLM (2.5GB)
                gliner.unload()

                if let llm {
                    let detectedPersons = merged.filter { $0.type == .person }.map(\.text)
                    let detectedPlaces = merged.filter { $0.type == .place }.map(\.text)
                    let knownEntities = KnownEntities(personnes: detectedPersons, lieux: detectedPlaces, themes: [])

                    do {
                        AppLogger.log("🤖 Vérification IA en cours…")
                        let result = try await llm.verifyEntities(
                            text: rawText,
                            relations: relations,
                            knownEntities: knownEntities
                        )

                        var correctedRelations: [EntityRelation] = []
                        for verified in result.correctedEvents {
                            correctedRelations.append(EntityRelation(
                                event: verified.title,
                                eventType: .activity,
                                persons: verified.persons,
                                locations: verified.location.map { [$0] } ?? [],
                                description: verified.excerpt
                            ))
                        }

                        if !correctedRelations.isEmpty {
                            lastRelations = correctedRelations
                            AppLogger.log("✅ Vérification IA: \(correctedRelations.count) événements corrigés")
                            if let toolExecutor {
                                try toolExecutor.replaceStructuredEvents(with: correctedRelations, for: entry)
                            }
                        }

                        updateStep(3, status: .done)
                    } catch {
                        AppLogger.log("⚠️ Vérification IA: \(error)")
                        updateStep(3, status: .failed)
                    }

                    // ── Étape 5 : Résumé narratif ──
                    updateStep(4, status: .active)

                    if let viewContext {
                        do {
                            let narrativeService = NarrativeService(llmService: llm, context: viewContext)
                            let summary = try await narrativeService.generateDailySummary(for: entry)
                            dailySummary = summary
                            dailyTitle = entry.titre ?? ""
                            updateStep(4, status: .done)
                        } catch {
                            AppLogger.log("⚠️ Résumé quotidien: \(error)")
                            updateStep(4, status: .failed)
                        }
                    }
                } else {
                    updateStep(3, status: .failed)
                }

                // Tout est prêt — afficher les résultats
                state = .done

                // Moment opportun pour demander la permission notifications :
                // l'utilisateur vient de vivre la valeur de l'app
                await NotificationService.shared.requestPermissionIfNeeded()

            } catch {
                AppLogger.log("❌ Erreur pipeline: \(error)")
                state = .error("Erreur : \(error.localizedDescription)")
            }
        }
    }

    private func updateStep(_ index: Int, status: PipelineStep.StepStatus) {
        guard index < pipelineSteps.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            pipelineSteps[index].status = status
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
        lastRelations = []
        elapsedTime = 0
        audioLevels = Array(repeating: 0, count: 40)
        llmStatus = ""
        pipelineSteps = []
        isVerifying = false
        isGeneratingSummary = false
        dailySummary = ""
        dailyTitle = ""
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
            AppLogger.log("✏️ Tag modifié: \(segment.text) → \(newText) [\(type.rawValue)]")
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
