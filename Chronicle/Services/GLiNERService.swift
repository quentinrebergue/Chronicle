import Foundation
import OnnxRuntimeBindings
import Tokenizers

struct GLiNEREntity {
    let text: String
    let label: String
    let score: Float
    let startIdx: Int
    let endIdx: Int
}

final class GLiNERService {
    private var session: ORTSession?
    private var env: ORTEnv?
    private var hfTokenizer: Tokenizers.Tokenizer?
    private let maxWidth = 8

    let defaultEntityTypes = ["person", "location", "event", "activity"]

    enum GLiNERError: Error, LocalizedError {
        case modelNotFound
        case tokenizerNotFound
        case inferenceFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotFound: return "Modèle GLiNER introuvable"
            case .tokenizerNotFound: return "Tokenizer GLiNER introuvable"
            case .inferenceFailed(let msg): return "GLiNER: \(msg)"
            }
        }
    }

    // MARK: - Setup

    func unload() {
        session = nil
        env = nil
        hfTokenizer = nil
        AppLogger.log("🧹 GLiNER déchargé de la RAM")
    }

    var isLoaded: Bool { session != nil }

    func load() async throws {
        if isLoaded { return }
        guard let modelPath = Bundle.main.path(forResource: "gliner2_base", ofType: "onnx") else {
            throw GLiNERError.modelNotFound
        }

        guard let tokenizerPath = Bundle.main.path(forResource: "tokenizer2", ofType: "json") else {
            throw GLiNERError.tokenizerNotFound
        }

        env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setGraphOptimizationLevel(.all)
        session = try ORTSession(env: env!, modelPath: modelPath, sessionOptions: options)

        // Create temp dir with tokenizer files for AutoTokenizer
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("gliner2-tokenizer")
        try? FileManager.default.removeItem(at: tmpDir)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: tokenizerPath),
            to: tmpDir.appendingPathComponent("tokenizer.json")
        )
        // Create minimal tokenizer_config.json (Unigram/SentencePiece model)
        let configJSON = #"{"tokenizer_class":"XLMRobertaTokenizer"}"#
        try configJSON.write(to: tmpDir.appendingPathComponent("tokenizer_config.json"), atomically: true, encoding: .utf8)

        hfTokenizer = try await AutoTokenizer.from(modelFolder: tmpDir)
        AppLogger.log("✅ GLiNER2 chargé (modèle + tokenizer)")
    }

    // MARK: - Public API

    func extractEntities(from text: String, entityTypes: [String]? = nil) throws -> [GLiNEREntity] {
        guard let session, let hfTokenizer else {
            AppLogger.log("⚠️ GLiNER2: session ou tokenizer non chargé")
            return []
        }

        let types = entityTypes ?? defaultEntityTypes
        let normalizedText = normalizeText(text)

        let (feeds, words) = buildInputs(text: normalizedText, labels: types, tokenizer: hfTokenizer)
        AppLogger.log("🔧 GLiNER2 inputs: \(words.count) mots, \(feeds.inputIds.count) tokens")

        let scores = try runInference(feeds: feeds, numLabels: types.count, numWords: words.count)

        // Use normalizedText for position mapping since words come from it
        let entities = decodeEntities(scores: scores, words: words, labels: types, text: normalizedText)

        // Remap entity text to original text
        let remapped = entities.compactMap { entity -> GLiNEREntity? in
            guard let range = text.range(of: entity.text.trimmingCharacters(in: .whitespaces), options: .caseInsensitive) else { return nil }
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)
            return GLiNEREntity(text: String(text[range]), label: entity.label, score: entity.score, startIdx: start, endIdx: end)
        }

        AppLogger.log("🟢 GLiNER2: \(remapped.map { "[\($0.label):\($0.text) \(String(format: "%.0f", $0.score * 100))%]" })")
        return remapped
    }

    // MARK: - Text normalization

    private func normalizeText(_ text: String) -> String {
        var result = text
        let punctuation: [Character] = [",", ".", "!", "?", ";", ":", "\"", "(", ")", "[", "]", "–", "—"]
        for p in punctuation {
            result = result.replacingOccurrences(of: String(p), with: " \(p) ")
        }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Word splitting

    private struct WordToken {
        let text: String
        let start: Int
        let end: Int
    }

    private func splitWords(_ text: String) -> [WordToken] {
        // Match word characters (including apostrophes/hyphens within words) or single non-space chars
        let pattern = #"\w+(?:[-']\w+)*|\S"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var tokens: [WordToken] = []

        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match, let range = Range(match.range, in: text) else { return }
            let word = String(text[range])
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)
            tokens.append(WordToken(text: word, start: start, end: end))
        }

        return tokens
    }

    // MARK: - Build inputs

    private struct ModelFeeds {
        let inputIds: [Int64]
        let attentionMask: [Int64]
        let textPositions: [Int64]
        let schemaPositions: [Int64]
        let spanIdx: [Int64]
        let numSpans: Int
    }

    private func buildInputs(text: String, labels: [String], tokenizer: Tokenizers.Tokenizer) -> (ModelFeeds, [WordToken]) {
        let words = splitWords(text)
        let wordStrings = words.map { $0.text.lowercased() }

        // Schema tokens: ( [P] entities ( [E] label1 [E] label2 ... ) ) [SEP_TEXT] word1 word2 ...
        var schemaTokens = ["(", "[P]", "entities", "("]
        for label in labels {
            schemaTokens.append("[E]")
            schemaTokens.append(contentsOf: label.split(separator: " ").map(String.init))
        }
        schemaTokens.append(")")
        schemaTokens.append(")")

        let fullSequence = schemaTokens + ["[SEP_TEXT]"] + wordStrings
        let numSchemaWords = schemaTokens.count + 1 // +1 for [SEP_TEXT]

        // Special token IDs
        let specialTokenIds: [String: Int] = [
            "[P]": 128003, "[E]": 128005, "[SEP_TEXT]": 128002,
            "(": 287, ")": 1263
        ]

        // Tokenize each word separately and track word IDs
        var tokenIds: [Int] = []
        var wordIds: [Int] = []

        for (wordIdx, word) in fullSequence.enumerated() {
            if let specialId = specialTokenIds[word] {
                tokenIds.append(specialId)
                wordIds.append(wordIdx)
            } else {
                let ids = tokenizer.encode(text: word, addSpecialTokens: false)
                for id in ids {
                    tokenIds.append(id)
                    wordIds.append(wordIdx)
                }
            }
        }

        let seqLen = tokenIds.count
        let inputIds = tokenIds.map { Int64($0) }
        let attentionMask = [Int64](repeating: 1, count: seqLen)

        // text_positions: first token index for each text word
        var textPositions: [Int64] = []
        for wordIdx in 0..<wordStrings.count {
            let fullWordIdx = numSchemaWords + wordIdx
            var firstToken: Int? = nil
            for (tokPos, wid) in wordIds.enumerated() {
                if wid == fullWordIdx {
                    firstToken = tokPos
                    break
                }
            }
            if firstToken == nil {
                AppLogger.log("⚠️ GLiNER2: word '\(wordStrings[wordIdx])' not found in token mapping")
            }
            textPositions.append(Int64(firstToken ?? 0))
        }

        // schema_positions: [P] position, then each [E] position
        var schemaPositions: [Int64] = []
        for (i, tok) in schemaTokens.enumerated() {
            if tok == "[P]" || tok == "[E]" {
                for (tokPos, wid) in wordIds.enumerated() {
                    if wid == i {
                        schemaPositions.append(Int64(tokPos))
                        break
                    }
                }
            }
        }

        // span_idx
        let numWords = wordStrings.count
        var spans: [Int64] = []
        for start in 0..<numWords {
            for width in 1...maxWidth {
                let end = start + width
                if end <= numWords {
                    spans.append(Int64(start))
                    spans.append(Int64(end - 1))
                } else {
                    spans.append(0)
                    spans.append(0)
                }
            }
        }
        let numSpans = numWords * maxWidth

        let feeds = ModelFeeds(
            inputIds: inputIds,
            attentionMask: attentionMask,
            textPositions: textPositions,
            schemaPositions: schemaPositions,
            spanIdx: spans,
            numSpans: numSpans
        )

        return (feeds, words)
    }

    // MARK: - ONNX Inference

    private func runInference(feeds: ModelFeeds, numLabels: Int, numWords: Int) throws -> [Float] {
        guard let session else { throw GLiNERError.inferenceFailed("No session") }

        let seqLen = Int64(feeds.inputIds.count)
        let numSpans = Int64(feeds.numSpans)

        let inputIdsTensor = try createTensor(feeds.inputIds, shape: [1, seqLen])
        let attMaskTensor = try createTensor(feeds.attentionMask, shape: [1, seqLen])
        let textPosTensor = try createTensor(feeds.textPositions, shape: [Int64(feeds.textPositions.count)])
        let schemaPosTensor = try createTensor(feeds.schemaPositions, shape: [Int64(feeds.schemaPositions.count)])
        let spanIdxTensor = try createTensor(feeds.spanIdx, shape: [1, numSpans, 2])

        let inputDict: [String: ORTValue] = [
            "input_ids": inputIdsTensor,
            "attention_mask": attMaskTensor,
            "text_positions": textPosTensor,
            "schema_positions": schemaPosTensor,
            "span_idx": spanIdxTensor,
        ]

        let results = try session.run(
            withInputs: inputDict,
            outputNames: Set(["span_scores"]),
            runOptions: nil
        )

        guard let scoresValue = results["span_scores"] else {
            throw GLiNERError.inferenceFailed("No span_scores output")
        }

        let info = try scoresValue.tensorTypeAndShapeInfo()
        AppLogger.log("🔧 GLiNER2 output shape: \(info.shape)")

        let scoresData = try scoresValue.tensorData() as Data
        let floatCount = scoresData.count / MemoryLayout<Float>.size
        var scores = [Float](repeating: 0, count: floatCount)
        scoresData.withUnsafeBytes { buffer in
            let src = buffer.bindMemory(to: Float.self)
            for i in 0..<floatCount { scores[i] = src[i] }
        }

        return scores
    }

    private func createTensor(_ data: [Int64], shape: [Int64]) throws -> ORTValue {
        let nsShape = shape.map { NSNumber(value: $0) }
        var mutableData = data
        let tensorData = NSMutableData(bytes: &mutableData, length: data.count * MemoryLayout<Int64>.size)
        return try ORTValue(tensorData: tensorData, elementType: .int64, shape: nsShape)
    }

    // MARK: - Post-processing

    private func decodeEntities(scores: [Float], words: [WordToken], labels: [String], text: String, threshold: Float = 0.5) -> [GLiNEREntity] {
        // span_scores shape: (1, num_fields, num_words, max_width)
        // Already squeezed to (num_fields, num_words, max_width) via scores[0]
        let numFields = labels.count
        let numWords = words.count
        let mw = maxWidth

        var entities: [GLiNEREntity] = []

        for fieldIdx in 0..<numFields {
            for start in 0..<numWords {
                for widthIdx in 0..<mw {
                    let idx = fieldIdx * numWords * mw + start * mw + widthIdx
                    guard idx < scores.count else { continue }

                    let score = scores[idx]
                    if score >= threshold {
                        let end = start + widthIdx
                        guard end < words.count else { continue }

                        // Remap to original text positions
                        let charStart = words[start].start
                        let charEnd = words[end].end
                        let startStringIdx = text.index(text.startIndex, offsetBy: charStart, limitedBy: text.endIndex) ?? text.startIndex
                        let endStringIdx = text.index(text.startIndex, offsetBy: charEnd, limitedBy: text.endIndex) ?? text.endIndex
                        let entityText = String(text[startStringIdx..<endStringIdx])

                        entities.append(GLiNEREntity(
                            text: entityText, label: labels[fieldIdx],
                            score: score, startIdx: charStart, endIdx: charEnd
                        ))
                    }
                }
            }
        }

        // Greedy non-overlapping (highest score first)
        entities.sort { $0.score > $1.score }
        var selected: [GLiNEREntity] = []
        for e in entities {
            let overlaps = selected.contains { !(e.endIdx <= $0.startIdx || e.startIdx >= $0.endIdx) }
            if !overlaps { selected.append(e) }
        }

        selected.sort { $0.startIdx < $1.startIdx }
        return selected
    }
}
