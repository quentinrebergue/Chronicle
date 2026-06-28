import Foundation
import Hub
import MLXLLM
import MLXLMCommon
import Tokenizers

final class LLMService: ObservableObject {
    @Published var isLoaded = false
    @Published var isGenerating = false

    private var modelContainer: ModelContainer?

    enum Model: String, CaseIterable {
        case qwen3_1_7B = "mlx-community/Qwen3-1.7B-4bit"
        case qwen3_4B = "mlx-community/Qwen3-4B-4bit"
    }

    var currentModel: Model = .qwen3_1_7B

    enum LLMError: Error, LocalizedError {
        case modelNotLoaded

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded: return "Le modèle LLM n'est pas chargé"
            }
        }
    }

    func downloadModel(_ model: Model? = nil) async throws {
        if let model { currentModel = model }
        let downloader = HubDownloader()
        let repo = Hub.Repo(id: currentModel.rawValue)

        print("📥 Vérification modèle \(currentModel.rawValue)…")
        _ = try await downloader.download(
            id: currentModel.rawValue,
            revision: nil,
            matching: ["*.safetensors", "*.json", "tokenizer.*"],
            useLatest: false
        ) { progress in
            let percent = Int(progress.fractionCompleted * 100)
            let completed = ByteCountFormatter.string(fromByteCount: progress.completedUnitCount, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: progress.totalUnitCount, countStyle: .file)
            print("📦 Téléchargement: \(percent)% — \(completed) / \(total)")
        }
        print("✅ Modèle téléchargé sur le disque")
    }

    func loadModel(_ model: Model? = nil) async throws {
        if let model { currentModel = model }
        let config = ModelConfiguration(
            id: currentModel.rawValue
        )

        let downloader = HubDownloader()
        let tokenizerLoader = HFTokenizerLoader()

        modelContainer = try await LLMModelFactory.shared.loadContainer(
            from: downloader,
            using: tokenizerLoader,
            configuration: config
        ) { _ in }

        await MainActor.run { isLoaded = true }
        print("✅ Modèle LLM chargé en RAM")
    }

    func unloadModel() async {
        modelContainer = nil
        await MainActor.run { isLoaded = false }
        print("🗑️ Modèle LLM déchargé de la RAM")
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
    }

    func verifyEntities(text: String, relations: [EntityRelation], knownEntities: KnownEntities) async throws -> VerificationResult {
        guard let modelContainer else { throw LLMError.modelNotLoaded }

        await MainActor.run { isGenerating = true }
        defer { Task { @MainActor in isGenerating = false } }

        // Construire le résumé des relations à vérifier
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
        if !knownEntities.themes.isEmpty {
            knownContext += "Thèmes connus: \(knownEntities.themes.joined(separator: ", "))\n"
        }

        let prompt = """
            /no_think
            Tu vérifies des entités extraites automatiquement d'un journal vocal.

            \(knownContext)
            Événements extraits automatiquement :
            \(relationsText)
            Règles :
            - Corrige les noms qui correspondent à des entités connues (ex: House → Howth si Howth est connu)
            - Supprime les faux positifs (mots courants détectés comme personnes/lieux)
            - Corrige les attributions personne/lieu si elles sont fausses
            - Si un lieu ou une personne est inconnu, mets —
            - Retourne UNIQUEMENT la liste corrigée, une ligne par événement :
            titre | lieu | personnes (séparées par des virgules)
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

        let cleaned = Self.stripThinkingTags(fullText).trimmingCharacters(in: .whitespacesAndNewlines)
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

            if !title.isEmpty {
                events.append(VerifiedEvent(title: title, location: location, persons: persons))
            }
        }

        return VerificationResult(correctedEvents: events)
    }

    // MARK: - Résumé narratif

    func generateSummary(prompt: String) async throws -> String {
        guard let modelContainer else { throw LLMError.modelNotLoaded }

        await MainActor.run { isGenerating = true }
        defer { Task { @MainActor in isGenerating = false } }

        let messages: [Message] = [
            ["role": "system", "content": NarrativePrompts.summarizer],
            ["role": "user", "content": prompt]
        ]

        let userInput = UserInput(messages: messages)
        let lmInput = try await modelContainer.prepare(input: userInput)

        let stream = try await modelContainer.generate(
            input: lmInput,
            parameters: .init(temperature: 0.7)
        )

        var fullText = ""
        for await generation in stream {
            if let chunk = generation.chunk {
                fullText += chunk
            }
        }

        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard let range = text.range(of: "<think>[\\s\\S]*?</think>", options: .regularExpression) else {
            if let start = text.range(of: "<think>") {
                return String(text[..<start.lowerBound])
            }
            return text
        }
        return text.replacingCharacters(in: range, with: "")
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
