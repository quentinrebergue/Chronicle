import Foundation
import NaturalLanguage

struct DetectedEntity: Equatable {
    enum EntityType: String {
        case person
        case place
        case organization
        case event
        case activity
    }

    let text: String
    let type: EntityType
    let range: Range<String.Index>
}

final class NLPService {
    private let placePatterns: [(pattern: String, captureGroup: Int)] = [
        (#"(?:l'île de |île de |l'ile de )(\p{Lu}\w+)"#, 1),
        (#"(?:à |au |aux |en |sur |vers |de |du )(\p{Lu}\w+(?:[- ]\p{Lu}\w+)*)"#, 1),
        (#"(?:la |le |les )(\p{Lu}\w+(?:[- ]\p{Lu}\w+)*)(?= ?,| \.| et | puis| donc| où)"#, 1),
    ]

    private let personPatterns: [(pattern: String, captureGroup: Int)] = [
        (#"(?:mon ami |ma amie |mon amie |mon pote |mon frère |ma sœur |mon collègue )(\p{Lu}\w+)"#, 1),
        (#"(?:avec |chez )(\p{Lu}\p{Ll}+)(?= |,|\.|\z)"#, 1),
    ]

    func detectEntities(in text: String) -> [DetectedEntity] {
        var entities: [DetectedEntity] = []

        // 1. NLTagger (Apple NLP)
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            guard let tag else { return true }

            let entityType: DetectedEntity.EntityType? = switch tag {
            case .personalName: .person
            case .placeName: .place
            case .organizationName: .organization
            default: nil
            }

            if let entityType {
                entities.append(DetectedEntity(text: String(text[range]), type: entityType, range: range))
            }
            return true
        }

        // 2. Pattern matching pour les lieux
        for (pattern, group) in placePatterns {
            entities.append(contentsOf: matchPattern(pattern, group: group, type: .place, in: text, excluding: entities))
        }

        // 3. Pattern matching pour les personnes
        for (pattern, group) in personPatterns {
            entities.append(contentsOf: matchPattern(pattern, group: group, type: .person, in: text, excluding: entities))
        }

        // Dédupliquer (même texte, même position)
        var seen = Set<String>()
        entities = entities.filter { entity in
            let key = "\(entity.text)-\(entity.range.lowerBound)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        return entities
    }

    private func matchPattern(
        _ pattern: String,
        group: Int,
        type: DetectedEntity.EntityType,
        in text: String,
        excluding existing: [DetectedEntity]
    ) -> [DetectedEntity] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        var results: [DetectedEntity] = []
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)

        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match,
                  let captureRange = Range(match.range(at: group), in: text) else { return }

            let captured = String(text[captureRange])

            // Filtrer les mots communs qui ne sont pas des entités
            let commonWords: Set<String> = [
                "Donc", "Et", "Ensuite", "Enfin", "Puis", "Après",
                "Quand", "Il", "Elle", "On", "Je", "Les", "La", "Le",
                "Franchement", "Vraiment"
            ]
            if commonWords.contains(captured) { return }

            // Ne pas ajouter si déjà détecté à cette position
            let overlaps = existing.contains { $0.range.overlaps(captureRange) }
            if overlaps { return }

            results.append(DetectedEntity(text: captured, type: type, range: captureRange))
        }

        return results
    }
}
