import Foundation
import Hub
import MLXLLM
import MLXLMCommon
import Tokenizers

final class LLMService: ObservableObject {
    @Published var isLoaded = false
    @Published var isGenerating = false

    private var modelContainer: ModelContainer?

    enum LLMError: Error, LocalizedError {
        case modelNotLoaded

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded: return "Le modèle LLM n'est pas chargé"
            }
        }
    }

    func loadModel() async throws {
        let config = ModelConfiguration(
            id: "mlx-community/Qwen3-1.7B-4bit"
        )

        let downloader = HubDownloader()
        let tokenizerLoader = HFTokenizerLoader()

        modelContainer = try await LLMModelFactory.shared.loadContainer(
            from: downloader,
            using: tokenizerLoader,
            configuration: config
        ) { progress in
            let percent = Int(progress.fractionCompleted * 100)
            let completed = ByteCountFormatter.string(fromByteCount: progress.completedUnitCount, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: progress.totalUnitCount, countStyle: .file)
            print("📦 Modèle: \(percent)% — \(completed) / \(total) — fichiers: \(progress.completedUnitCount)/\(progress.totalUnitCount)")
        }

        await MainActor.run { isLoaded = true }
    }

    func processTranscription(
        rawText: String,
        knownEntities: KnownEntities
    ) async throws -> LLMResult {
        guard let modelContainer else { throw LLMError.modelNotLoaded }

        await MainActor.run { isGenerating = true }
        defer { Task { @MainActor in isGenerating = false } }

        let systemPrompt = buildSystemPrompt(entities: knownEntities)

        let messages: [Message] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": rawText]
        ]

        let userInput = UserInput(messages: messages, tools: ToolDefinitions.all)
        let lmInput = try await modelContainer.prepare(input: userInput)

        let stream = try await modelContainer.generate(
            input: lmInput,
            parameters: .init(temperature: 0.3)
        )

        var fullText = ""
        var toolCalls: [ChronicleToolCall] = []

        for await generation in stream {
            switch generation {
            case .chunk(let text):
                fullText += text
            case .toolCall(let call):
                let args = call.function.arguments.reduce(into: [String: String]()) { result, pair in
                    switch pair.value {
                    case .string(let s):
                        result[pair.key] = s
                    case .int(let i):
                        result[pair.key] = "\(i)"
                    case .double(let d):
                        result[pair.key] = "\(d)"
                    case .bool(let b):
                        result[pair.key] = "\(b)"
                    default:
                        result[pair.key] = "\(pair.value)"
                    }
                }
                toolCalls.append(ChronicleToolCall(name: call.function.name, arguments: args))
            case .info:
                break
            }
        }

        let cleaned = Self.stripThinkingTags(fullText).trimmingCharacters(in: .whitespacesAndNewlines)

        return LLMResult(
            correctedText: cleaned.isEmpty ? rawText : cleaned,
            toolCalls: toolCalls
        )
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

    private func buildSystemPrompt(entities: KnownEntities) -> String {
        var prompt = """
            /no_think
            Tu es l'assistant de transcription de l'utilisateur.

            IMPORTANT : Tu DOIS utiliser les outils disponibles pour extraire les entités.
            Pour chaque lieu mentionné → appelle createPlace
            Pour chaque personne mentionnée → appelle createPerson
            Pour chaque événement → appelle createEvent
            Pour l'émotion générale → appelle setEmotion

            Après les appels d'outils, retourne UNIQUEMENT le texte corrigé sans explication.
            Si des entités connues correspondent à des mots mal transcrits, corrige-les.

            """

        if !entities.personnes.isEmpty {
            prompt += "Personnes connues : \(entities.personnes.joined(separator: ", "))\n"
        }
        if !entities.lieux.isEmpty {
            prompt += "Lieux connus : \(entities.lieux.joined(separator: ", "))\n"
        }
        if !entities.themes.isEmpty {
            prompt += "Thèmes connus : \(entities.themes.joined(separator: ", "))\n"
        }

        return prompt
    }
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

// MARK: - Types

struct KnownEntities {
    var personnes: [String] = []
    var lieux: [String] = []
    var themes: [String] = []
}

struct LLMResult {
    let correctedText: String
    let toolCalls: [ChronicleToolCall]
}

struct ChronicleToolCall {
    let name: String
    let arguments: [String: String]
}
