import Foundation
import Hub
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

final class LLMService: ObservableObject {
    @Published var isLoaded = false
    @Published var isGenerating = false

    private var modelContainer: ModelContainer?

    enum Model: String, CaseIterable {
        case qwen3_5_4B = "mlx-community/Qwen3.5-4B-4bit"
        case qwen3_4B = "mlx-community/Qwen3-4B-4bit"
        case qwen3_1_7B = "mlx-community/Qwen3-1.7B-4bit"
    }

    var currentModel: Model = .qwen3_5_4B

    enum LLMError: Error, LocalizedError {
        case modelNotLoaded

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded: return "Le modèle LLM n'est pas chargé"
            }
        }
    }

    private static func downloadedKey(for model: Model) -> String {
        "otobio.modelVerified.\(model.rawValue)"
    }

    /// Une fois le modèle vérifié une première fois, on saute la vérification réseau
    /// (l'appel Hub prend ~10-15s même quand tout est déjà en cache local, à chaque lancement).
    func downloadModel(_ model: Model? = nil) async throws {
        if let model { currentModel = model }
        let key = Self.downloadedKey(for: currentModel)

        if UserDefaults.standard.bool(forKey: key) {
            AppLogger.log("✅ Modèle déjà vérifié lors d'un lancement précédent, skip réseau")
            return
        }

        let downloader = HubDownloader()
        _ = Hub.Repo(id: currentModel.rawValue)

        AppLogger.log("📥 Vérification modèle \(currentModel.rawValue)…")
        _ = try await downloader.download(
            id: currentModel.rawValue,
            revision: nil,
            matching: ["*.safetensors", "*.json", "tokenizer.*"],
            useLatest: false
        ) { progress in
            let percent = Int(progress.fractionCompleted * 100)
            let completed = ByteCountFormatter.string(fromByteCount: progress.completedUnitCount, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: progress.totalUnitCount, countStyle: .file)
            AppLogger.log("📦 Téléchargement: \(percent)% — \(completed) / \(total)")
        }
        AppLogger.log("✅ Modèle téléchargé sur le disque")
        UserDefaults.standard.set(true, forKey: key)
    }

    func loadModel(_ model: Model? = nil) async throws {
        if modelContainer != nil {
            AppLogger.log("✅ Modèle LLM déjà en RAM, skip load")
            return
        }
        if let model { currentModel = model }
        let config = ModelConfiguration(
            id: currentModel.rawValue
        )

        let downloader = HubDownloader()
        let tokenizerLoader = HFTokenizerLoader()

        AppLogger.log("⏳ Chargement du modèle \(currentModel.rawValue) en RAM…")
        modelContainer = try await LLMModelFactory.shared.loadContainer(
            from: downloader,
            using: tokenizerLoader,
            configuration: config
        ) { _ in }

        await MainActor.run { isLoaded = true }
        AppLogger.log("✅ Modèle LLM chargé en RAM")
    }

    func unloadModel() async {
        modelContainer = nil
        await MainActor.run { isLoaded = false }
        AppLogger.log("🗑️ Modèle LLM déchargé de la RAM")
    }

    // MARK: - NER : extraction d'entités

    func extractEntities(from text: String) async throws -> [LLMEntity] {
        guard let modelContainer else { throw LLMError.modelNotLoaded }

        await MainActor.run { isGenerating = true }
        defer { Task { @MainActor in isGenerating = false } }

        let prompt = """
            /no_think
            Extrais les entités du texte suivant. Retourne UNIQUEMENT une liste, une entité par ligne, dans ce format exact :
            TYPE:nom

            Types possibles : PERSONNE, LIEU, EVENEMENT, ACTIVITE

            Règles :
            - PERSONNE : prénoms ou noms de personnes mentionnées
            - LIEU : villes, pays, îles, rues, bâtiments, restaurants, etc.
            - EVENEMENT : événements spécifiques (Pride, fête, concert, etc.)
            - ACTIVITE : activités faites (trail, café, rangement, etc.)

            Retourne UNIQUEMENT la liste, rien d'autre. Pas de numéros, pas de tirets.
            """

        let messages: [Message] = [
            ["role": "system", "content": prompt],
            ["role": "user", "content": text]
        ]

        let userInput = UserInput(messages: messages)
        let lmInput = try await modelContainer.prepare(input: userInput)

        let stream = try await modelContainer.generate(
            input: lmInput,
            parameters: .init(temperature: 0.1)
        )

        var fullText = ""
        for await generation in stream {
            if let chunk = generation.chunk {
                fullText += chunk
            }
        }

        let cleaned = Self.stripThinkingTags(fullText)
        return Self.parseEntities(cleaned, sourceText: text)
    }

    // MARK: - Vérification des entités

    struct VerificationResult {
        let correctedEvents: [VerifiedEvent]
    }

    struct VerifiedEvent {
        let title: String
        let location: String?
        let persons: [String]
        let excerpt: String
    }

    func verifyEntities(text: String, relations: [EntityRelation], knownEntities: KnownEntities) async throws -> VerificationResult {
        await MainActor.run { isGenerating = true }
        defer { Task { @MainActor in isGenerating = false } }

        var relationsText = ""
        for r in relations {
            let p = r.persons.isEmpty ? "—" : r.persons.joined(separator: ", ")
            let l = r.locations.isEmpty ? "—" : r.locations.joined(separator: ", ")
            relationsText += "- \(r.event) | lieu: \(l) | personnes: \(p)\n"
        }

        var knownContext = ""
        if !knownEntities.personnes.isEmpty {
            knownContext += "Personnes connues: \(knownEntities.personnes.joined(separator: ", "))\n"
        }
        if !knownEntities.lieux.isEmpty {
            knownContext += "Lieux connus: \(knownEntities.lieux.joined(separator: ", "))\n"
        }

        let systemPrompt = """
            Tu corriges des événements extraits automatiquement d'un journal vocal français.
            Réponds UNIQUEMENT avec la liste corrigée, une ligne par événement, ce format exact :
            titre | lieu | personnes | extrait
            Utilise — si pas de lieu ou de personnes.
            L'extrait est le passage du texte original lié à cet événement (copié tel quel, peut couvrir plusieurs phrases).
            """

        let userPrompt = """
            \(knownContext)
            Texte original :
            \(text)

            Événements détectés automatiquement :
            \(relationsText)
            Corrige :
            - Les noms mal transcrits (ex: "House" → "Howth" si c'est un lieu connu)
            - Les faux positifs (ex: "douche" n'est pas un événement notable)
            - Les mauvaises attributions personne/lieu
            - Ajoute les événements manqués (ex: un événement mentionné dans le texte mais pas détecté)
            - Mets un titre court et descriptif pour chaque événement
            - Pour chaque événement, copie le passage du texte original correspondant dans le champ extrait
            """

        AppLogger.log("🤖 Vérification: chargement modèle…")
        try await loadModel()

        let messages: [Message] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]

        let userInput = UserInput(messages: messages, additionalContext: ["enable_thinking": false])
        AppLogger.log("🤖 Vérification: prepare()…")
        guard let container = modelContainer else { throw LLMError.modelNotLoaded }
        let lmInput = try await container.prepare(input: userInput)

        AppLogger.log("🤖 Vérification: generate() (max 500 tokens)…")
        let stream = try await container.generate(
            input: lmInput,
            parameters: .init(maxTokens: 500, temperature: 0.1)
        )

        var fullText = ""
        var tokenCount = 0
        for await generation in stream {
            if let chunk = generation.chunk {
                fullText += chunk
                tokenCount += 1
                if tokenCount % 20 == 0 {
                    AppLogger.log("🤖 Vérification: \(tokenCount) tokens…")
                }
            }
        }

        let cleaned = Self.stripThinkingTags(fullText)
        AppLogger.log("🤖 Vérification terminée: \(tokenCount) tokens → \(cleaned.prefix(200))…")

        Memory.clearCache()

        return Self.parseVerification(cleaned)
    }

    private static func parseVerification(_ text: String) -> VerificationResult {
        var events: [VerifiedEvent] = []

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
            let parts = trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { continue }

            let title = parts[0]
            let location = parts.count > 1 && parts[1] != "—" && !parts[1].isEmpty ? parts[1] : nil
            let persons: [String] = parts.count > 2 && parts[2] != "—"
                ? parts[2].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                : []
            let excerpt = parts.count > 3 && parts[3] != "—" ? parts[3] : ""

            if !title.isEmpty {
                events.append(VerifiedEvent(title: title, location: location, persons: persons, excerpt: excerpt))
            }
        }

        return VerificationResult(correctedEvents: events)
    }

    // MARK: - Résumé narratif

    func generateSummary(prompt: String, maxTokens: Int = 300) async throws -> String {
        guard let modelContainer else { throw LLMError.modelNotLoaded }

        await MainActor.run { isGenerating = true }
        defer { Task { @MainActor in isGenerating = false } }

        AppLogger.log("🤖 Préparation du prompt (\(prompt.count) chars)…")

        let messages: [Message] = [
            ["role": "system", "content": NarrativePrompts.summarizer],
            ["role": "user", "content": prompt]
        ]

        let userInput = UserInput(messages: messages, additionalContext: ["enable_thinking": false])
        AppLogger.log("🤖 prepare() appelé…")
        let lmInput = try await modelContainer.prepare(input: userInput)
        AppLogger.log("🤖 prepare() terminé, lancement generate()…")
        let stream = try await modelContainer.generate(
            input: lmInput,
            parameters: .init(maxTokens: maxTokens, temperature: 0.7, topP: 0.9)
        )

        var fullText = ""
        var tokenCount = 0
        for await generation in stream {
            if let chunk = generation.chunk {
                fullText += chunk
                tokenCount += 1
                if tokenCount % 20 == 0 {
                    AppLogger.log("🤖 … \(tokenCount) tokens générés")
                }
            }
        }

        let cleaned = Self.stripThinkingTags(fullText).trimmingCharacters(in: .whitespacesAndNewlines)
        AppLogger.log("🤖 Généré: \(tokenCount) tokens, \(cleaned.count) chars output: \(cleaned.prefix(100))…")

        AppLogger.log("🤖 Nettoyage cache GPU…")
        Memory.clearCache()

        return cleaned
    }

    // MARK: - Parsing

    private static func parseEntities(_ text: String, sourceText: String) -> [LLMEntity] {
        var entities: [LLMEntity] = []

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }

            let typeStr = String(trimmed[trimmed.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces).uppercased()
            let name = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            guard !name.isEmpty else { continue }

            let type: LLMEntity.EntityType? = switch typeStr {
            case "PERSONNE": .person
            case "LIEU": .place
            case "EVENEMENT", "ÉVÉNEMENT": .event
            case "ACTIVITE", "ACTIVITÉ": .activity
            default: nil
            }

            guard let type else { continue }

            // Trouver la position dans le texte source
            let range = sourceText.range(of: name, options: .caseInsensitive)

            entities.append(LLMEntity(name: name, type: type, rangeInSource: range))
        }

        return entities
    }

    private static func stripThinkingTags(_ text: String) -> String {
        var result = text
        // Strip <think>...</think> blocks
        if let range = result.range(of: "<think>[\\s\\S]*?</think>", options: .regularExpression) {
            result = result.replacingCharacters(in: range, with: "")
        } else if let start = result.range(of: "<think>") {
            result = String(result[..<start.lowerBound])
        }
        // Strip "Thinking Process:" or similar prefixes
        if let range = result.range(of: "^\\s*(Thinking Process|Réflexion|Analyse)[:\\s]*[\\s\\S]*?\\n\\n", options: .regularExpression) {
            result = String(result[range.upperBound...])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Types

struct LLMEntity {
    enum EntityType: String {
        case person = "PERSONNE"
        case place = "LIEU"
        case event = "EVENEMENT"
        case activity = "ACTIVITE"
    }

    let name: String
    let type: EntityType
    let rangeInSource: Range<String.Index>?
}

struct LLMResult {
    let correctedText: String
    let emotion: String?
    let emotionIntensity: Int16?
}

// MARK: - Hugging Face Downloader

private struct HubDownloader: MLXLMCommon.Downloader {
    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let hubApi = HubApi()
        let repo = Hub.Repo(id: id)
        return try await hubApi.snapshot(
            from: repo,
            matching: patterns,
            progressHandler: progressHandler
        )
    }
}

// MARK: - Hugging Face Tokenizer Loader

private struct HFTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let hfTokenizer = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizerWrapper(hfTokenizer)
    }
}

private struct TokenizerWrapper: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
    }
}
