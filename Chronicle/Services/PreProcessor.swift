import Foundation
import CoreData

struct PreProcessingResult {
    let detectedEntities: [DetectedEntity]
    let suggestedCorrections: [SuggestedCorrection]
    let existingEntityNames: Set<String>
    let temporalContext: String
}

struct SuggestedCorrection {
    let original: String
    let suggested: String
    let confidence: Double
    let entityType: DetectedEntity.EntityType
}

final class PreProcessor {
    private let nlp = NLPService()
    private let viewContext: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.viewContext = context
    }

    func process(rawText: String) -> PreProcessingResult {
        let detected = nlp.detectEntities(in: rawText)
        let known = fetchKnownEntityNames()
        let corrections = findCorrections(detected: detected, known: known, rawText: rawText)
        let temporal = buildTemporalContext()

        print("🏷️ NLTagger entités: \(detected.map { "[\($0.type.rawValue):\($0.text)]" })")
        print("🔍 Corrections suggérées: \(corrections.map { "\($0.original) → \($0.suggested) (\(Int($0.confidence * 100))%)" })")

        return PreProcessingResult(
            detectedEntities: detected,
            suggestedCorrections: corrections,
            existingEntityNames: known,
            temporalContext: temporal
        )
    }

    private func findCorrections(detected: [DetectedEntity], known: Set<String>, rawText: String) -> [SuggestedCorrection] {
        var corrections: [SuggestedCorrection] = []

        for entity in detected {
            if known.contains(entity.text) { continue }

            for knownName in known {
                let score = fuzzyScore(entity.text, knownName)
                if score >= 0.75 && score < 1.0 {
                    corrections.append(SuggestedCorrection(
                        original: entity.text,
                        suggested: knownName,
                        confidence: score,
                        entityType: entity.type
                    ))
                }
            }
        }


        return corrections
    }

    private func fuzzyScore(_ a: String, _ b: String) -> Double {
        let s1 = a.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let s2 = b.lowercased().folding(options: .diacriticInsensitive, locale: .current)

        if s1 == s2 { return 1.0 }

        let distance = levenshtein(s1, s2)
        let maxLen = max(s1.count, s2.count)
        guard maxLen > 0 else { return 0 }

        return 1.0 - (Double(distance) / Double(maxLen))
    }

    private func levenshtein(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }

        return matrix[m][n]
    }

    func fetchKnownEntities() -> KnownEntities {
        var entities = KnownEntities()
        if let personnes = try? viewContext.fetch(Personne.fetchRequest()) {
            entities.personnes = personnes.compactMap(\.nom)
        }
        if let lieux = try? viewContext.fetch(Lieu.fetchRequest()) {
            entities.lieux = lieux.compactMap(\.nom)
        }
        if let themes = try? viewContext.fetch(Theme.fetchRequest()) {
            entities.themes = themes.compactMap(\.label)
        }
        return entities
    }

    private func fetchKnownEntityNames() -> Set<String> {
        var names = Set<String>()

        if let personnes = try? viewContext.fetch(Personne.fetchRequest()) {
            personnes.compactMap(\.nom).forEach { names.insert($0) }
        }
        if let lieux = try? viewContext.fetch(Lieu.fetchRequest()) {
            lieux.compactMap(\.nom).forEach { names.insert($0) }
        }
        if let themes = try? viewContext.fetch(Theme.fetchRequest()) {
            themes.compactMap(\.label).forEach { names.insert($0) }
        }
        if let events = try? viewContext.fetch(Evenement.fetchRequest()) {
            events.compactMap(\.titre).forEach { names.insert($0) }
        }

        return names
    }

    private func guessType(for entityName: String) -> DetectedEntity.EntityType? {
        if (try? viewContext.fetch(Personne.fetchRequest()))?.contains(where: { $0.nom == entityName }) == true {
            return .person
        }
        if (try? viewContext.fetch(Lieu.fetchRequest()))?.contains(where: { $0.nom == entityName }) == true {
            return .place
        }
        return nil
    }

    private func buildTemporalContext() -> String {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)

        let timeOfDay = switch hour {
        case 5..<12: "le matin"
        case 12..<14: "le midi"
        case 14..<18: "l'après-midi"
        case 18..<22: "le soir"
        default: "la nuit"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr-FR")
        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: now)

        let isWeekend = weekday == 1 || weekday == 7

        return "\(dayName) \(timeOfDay)\(isWeekend ? " (weekend)" : "")"
    }
}
