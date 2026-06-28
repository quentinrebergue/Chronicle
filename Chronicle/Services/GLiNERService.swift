import Foundation
import Tokenizers
import OnnxRuntimeBindings

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
    private var tokenizer: (any Tokenizer)?
    private let maxWidth = 12

    let defaultEntityTypes = ["person", "location", "event", "activity"]

    enum GLiNERError: Error, LocalizedError {
        case modelNotFound
        case tokenizerNotFound
        case sessionCreationFailed
        case inferenceFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotFound: return "Modèle GLiNER introuvable"
            case .tokenizerNotFound: return "Tokenizer GLiNER introuvable"
            case .sessionCreationFailed: return "Impossible de créer la session ONNX"
            case .inferenceFailed(let msg): return "Inférence GLiNER échouée: \(msg)"
            }
        }
    }

    // MARK: - Setup

    func load() async throws {
        guard let modelPath = Bundle.main.path(forResource: "gliner_small", ofType: "onnx") else {
            throw GLiNERError.modelNotFound
        }

        env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setGraphOptimizationLevel(.all)
        session = try ORTSession(env: env!, modelPath: modelPath, sessionOptions: options)

        // Create a temp directory with tokenizer files, patching the tokenizer_class
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("gliner-tokenizer")
        try? FileManager.default.removeItem(at: tmpDir)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let filesToCopy = ["tokenizer.json", "special_tokens_map.json", "added_tokens.json", "config.json"]
        for file in filesToCopy {
            let name = file.components(separatedBy: ".").first ?? file
            let ext = file.components(separatedBy: ".").last ?? ""
            if let src = Bundle.main.path(forResource: name, ofType: ext) {
                try FileManager.default.copyItem(
                    at: URL(fileURLWithPath: src),
                    to: tmpDir.appendingPathComponent(file)
                )
            }
        }

        // Patch tokenizer_config.json to use a supported tokenizer class
        if let src = Bundle.main.path(forResource: "tokenizer_config", ofType: "json") {
            var content = try String(contentsOfFile: src, encoding: .utf8)
            content = content.replacingOccurrences(of: "DebertaV2Tokenizer", with: "XLMRobertaTokenizer")
            try content.write(to: tmpDir.appendingPathComponent("tokenizer_config.json"), atomically: true, encoding: .utf8)
        }

        tokenizer = try await AutoTokenizer.from(modelFolder: tmpDir)
        print("✅ GLiNER chargé (modèle + tokenizer)")
    }

    // MARK: - Public API

    private func normalizeText(_ text: String) -> String {
        var result = text
        // Séparer la ponctuation SAUF les apostrophes (important pour le français : l'île, j'ai, c'est)
        let punctuation: [Character] = [",", ".", "!", "?", ";", ":", "\"", "(", ")", "[", "]", "–", "—"]
        for p in punctuation {
            result = result.replacingOccurrences(of: String(p), with: " \(p) ")
        }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static let commonWords: Set<String> = [
        "je", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles",
        "me", "te", "se", "le", "la", "les", "un", "une", "des",
        "ce", "cette", "ces", "mon", "ma", "mes", "ton", "ta", "tes",
        "son", "sa", "ses", "qui", "que", "quoi", "dont", "où",
        "et", "ou", "mais", "donc", "car", "ni", "de", "du", "au", "aux",
        "en", "à", "pour", "par", "sur", "dans", "avec", "sans",
        "puis", "ensuite", "enfin", "aussi", "très", "plus", "tout",
        "I", "he", "she", "we", "they", "the", "a", "an", "and", "or",
    ]

    func extractEntities(from text: String, entityTypes: [String]? = nil) throws -> [GLiNEREntity] {
        guard let session, let tokenizer else {
            print("⚠️ GLiNER: session ou tokenizer non chargé")
            return []
        }

        let types = entityTypes ?? defaultEntityTypes
        let normalizedText = normalizeText(text)
        print("🔧 GLiNER preprocessing: \(normalizedText.prefix(80))…")

        let inputs = prepareInputs(text: normalizedText, entities: types, tokenizer: tokenizer)
        print("🔧 GLiNER inputs: \(inputs.words.count) mots, \(inputs.seqLen) tokens, \(inputs.numSpans) spans")

        let logits: [Float]
        do {
            logits = try runInference(inputs: inputs)
            print("🔧 GLiNER inference OK: \(logits.count) logits")
        } catch {
            print("❌ GLiNER inference échouée: \(error)")
            throw error
        }

        let entities = decodeOutput(
            logits: logits,
            words: inputs.words,
            entities: types,
            text: text,
            numWords: inputs.words.count
        )

        // Remap entity positions to original text
        let remapped = entities.compactMap { entity -> GLiNEREntity? in
            guard let range = text.range(of: entity.text, options: .caseInsensitive) else { return nil }
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)
            return GLiNEREntity(text: entity.text, label: entity.label, score: entity.score, startIdx: start, endIdx: end)
        }

        print("🟢 GLiNER: \(remapped.map { "[\($0.label):\($0.text) \(String(format: "%.0f", $0.score * 100))%]" })")
        return remapped
    }

    // MARK: - Word splitting

    private struct WordToken {
        let text: String
        let start: Int
        let end: Int
    }

    private func splitWords(_ text: String) -> [WordToken] {
        var tokens: [WordToken] = []
        var i = text.startIndex

        while i < text.endIndex {
            while i < text.endIndex && text[i].isWhitespace { i = text.index(after: i) }
            guard i < text.endIndex else { break }

            let start = i
            while i < text.endIndex && !text[i].isWhitespace { i = text.index(after: i) }

            tokens.append(WordToken(
                text: String(text[start..<i]),
                start: text.distance(from: text.startIndex, to: start),
                end: text.distance(from: text.startIndex, to: i)
            ))
        }
        return tokens
    }

    // MARK: - Preprocessing

    private struct ModelInputs {
        let inputIds: [Int64]
        let attentionMask: [Int64]
        let wordsMask: [Int64]
        let textLengths: [Int64]
        let spanIdx: [Int64]
        let spanMask: [Int64]
        let words: [WordToken]
        let seqLen: Int
        let numSpans: Int
    }

    private func prepareInputs(text: String, entities: [String], tokenizer: any Tokenizer) -> ModelInputs {
        let words = splitWords(text)
        let textLength = words.count

        // Build prompt token IDs: <<ENT>> entity1 <<ENT>> entity2 <<SEP>> word1 word2 ...
        let entTokenId = 128002  // <<ENT>>
        let sepTokenId = 128003  // <<SEP>>

        var partTokenIds: [[Int]] = []
        for entity in entities {
            partTokenIds.append([entTokenId])
            partTokenIds.append(tokenizer.encode(text: entity, addSpecialTokens: false))
        }
        partTokenIds.append([sepTokenId])
        let promptLength = partTokenIds.count

        for word in words {
            partTokenIds.append(tokenizer.encode(text: word.text, addSpecialTokens: false))
        }

        // Debug: check token encoding
        let debugLabels = entities.flatMap { ["<<ENT>>", $0] } + ["<<SEP>>"] + words.prefix(3).map(\.text)
        for (i, label) in debugLabels.prefix(min(12, partTokenIds.count)).enumerated() {
            print("🔧 Token '\(label)' → \(partTokenIds[i])")
        }

        // Calculate total sequence length (BOS + tokens + EOS)
        var seqLen = 2
        for ids in partTokenIds { seqLen += ids.count }

        // Build arrays
        var inputIds = [Int64](repeating: 0, count: seqLen)
        var attentionMask = [Int64](repeating: 0, count: seqLen)
        var wordsMask = [Int64](repeating: 0, count: seqLen)

        var idx = 0
        inputIds[idx] = 1 // BOS
        attentionMask[idx] = 1
        idx += 1

        var wordId: Int64 = 1
        for (partIdx, ids) in partTokenIds.enumerated() {
            let isTextPart = partIdx >= promptLength

            if isTextPart {
                wordsMask[idx] = wordId
                wordId += 1
            }

            for id in ids {
                inputIds[idx] = Int64(id)
                attentionMask[idx] = 1
                idx += 1
            }
        }
        inputIds[idx] = 2 // EOS
        attentionMask[idx] = 1

        // Build spans
        let numSpans = textLength * maxWidth
        var spanIdx = [Int64](repeating: 0, count: numSpans * 2)
        var spanMask = [Int64](repeating: 0, count: numSpans)

        for i in 0..<textLength {
            let m = min(maxWidth, textLength - i)
            for j in 0..<m {
                let sIdx = i * maxWidth + j
                spanIdx[2 * sIdx] = Int64(i)
                spanIdx[2 * sIdx + 1] = Int64(i + j)
                spanMask[sIdx] = 1
            }
        }

        return ModelInputs(
            inputIds: inputIds, attentionMask: attentionMask, wordsMask: wordsMask,
            textLengths: [Int64(textLength)], spanIdx: spanIdx, spanMask: spanMask,
            words: words, seqLen: seqLen, numSpans: numSpans
        )
    }

    // MARK: - ONNX Inference

    private func runInference(inputs: ModelInputs) throws -> [Float] {
        guard let session else { throw GLiNERError.sessionCreationFailed }

        let batchSize: Int64 = 1
        let seqLen = Int64(inputs.seqLen)
        let numSpans = Int64(inputs.numSpans)

        let inputIdsTensor = try createTensor(inputs.inputIds, shape: [batchSize, seqLen])
        let attMaskTensor = try createTensor(inputs.attentionMask, shape: [batchSize, seqLen])
        let wordsMaskTensor = try createTensor(inputs.wordsMask, shape: [batchSize, seqLen])
        let textLenTensor = try createTensor(inputs.textLengths, shape: [batchSize, 1])
        let spanIdxTensor = try createTensor(inputs.spanIdx, shape: [batchSize, numSpans, 2])
        let spanMaskTensor = try createTensor(inputs.spanMask, shape: [batchSize, numSpans])

        let inputDict: [String: ORTValue] = [
            "input_ids": inputIdsTensor,
            "attention_mask": attMaskTensor,
            "words_mask": wordsMaskTensor,
            "text_lengths": textLenTensor,
            "span_idx": spanIdxTensor,
            "span_mask": spanMaskTensor
        ]

        let results = try session.run(
            withInputs: inputDict,
            outputNames: Set(["logits"]),
            runOptions: nil
        )

        guard let logitsValue = results["logits"] else {
            throw GLiNERError.inferenceFailed("No logits output")
        }

        let logitsInfo = try logitsValue.tensorTypeAndShapeInfo()
        print("🔧 GLiNER logits shape: \(logitsInfo.shape)")

        let logitsData = try logitsValue.tensorData() as Data
        let floatCount = logitsData.count / MemoryLayout<Float>.size
        print("🔧 GLiNER logits: \(floatCount) floats (\(logitsData.count) bytes)")

        var logits = [Float](repeating: 0, count: floatCount)
        logitsData.withUnsafeBytes { buffer in
            let floatBuffer = buffer.bindMemory(to: Float.self)
            for i in 0..<floatCount {
                logits[i] = floatBuffer[i]
            }
        }

        return logits
    }

    private func createBoolTensor(_ data: [Bool], shape: [Int64]) throws -> ORTValue {
        let nsShape = shape.map { NSNumber(value: $0) }
        var bytes = data.map { UInt8($0 ? 1 : 0) }
        let tensorData = NSMutableData(bytes: &bytes, length: bytes.count)
        return try ORTValue(
            tensorData: tensorData,
            elementType: .uInt8,
            shape: nsShape
        )
    }

    private func createTensor(_ data: [Int64], shape: [Int64]) throws -> ORTValue {
        let nsShape = shape.map { NSNumber(value: $0) }
        var mutableData = data
        let tensorData = NSMutableData(bytes: &mutableData, length: data.count * MemoryLayout<Int64>.size)
        return try ORTValue(
            tensorData: tensorData,
            elementType: .int64,
            shape: nsShape
        )
    }

    // MARK: - Post-processing

    private func decodeOutput(
        logits: [Float],
        words: [WordToken],
        entities: [String],
        text: String,
        numWords: Int,
        threshold: Float = 0.35
    ) -> [GLiNEREntity] {
        let numEntities = entities.count
        var spans: [GLiNEREntity] = []

        for startWord in 0..<numWords {
            let m = min(maxWidth, numWords - startWord)
            for spanWidth in 0..<m {
                let endWord = startWord + spanWidth
                for entityIdx in 0..<numEntities {
                    let logitIdx = startWord * maxWidth * numEntities + spanWidth * numEntities + entityIdx
                    guard logitIdx < logits.count else { continue }

                    let prob = sigmoid(logits[logitIdx])
                    if prob >= threshold {
                        let spanText = words[startWord...endWord].map(\.text).joined(separator: " ")

                        // Filtrer les mots communs (faux positifs)
                        let spanWords = spanText.lowercased().components(separatedBy: .whitespaces)
                        if spanWords.allSatisfy({ Self.commonWords.contains($0) }) { continue }
                        if spanText.count <= 3 && Self.commonWords.contains(spanText.lowercased()) { continue }

                        spans.append(GLiNEREntity(
                            text: spanText,
                            label: entities[entityIdx],
                            score: prob,
                            startIdx: words[startWord].start,
                            endIdx: words[endWord].end
                        ))
                    }
                }
            }
        }

        // Greedy non-overlapping selection (highest score first)
        spans.sort { $0.score > $1.score }
        var selected: [GLiNEREntity] = []
        for span in spans {
            let overlaps = selected.contains { existing in
                !(span.endIdx <= existing.startIdx || span.startIdx >= existing.endIdx)
            }
            if !overlaps { selected.append(span) }
        }

        selected.sort { $0.startIdx < $1.startIdx }
        return selected
    }

    private func sigmoid(_ x: Float) -> Float {
        1.0 / (1.0 + exp(-x))
    }
}
