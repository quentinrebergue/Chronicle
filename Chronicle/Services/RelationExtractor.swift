import Foundation

struct EntityRelation {
    var event: String
    var eventType: DetectedEntity.EntityType
    var persons: [String]
    var locations: [String]
    var description: String = ""
}

final class RelationExtractor {
    func extractRelations(from text: String, entities: [DetectedEntity]) -> [EntityRelation] {
        let sentences = splitSentences(text)
        var relations: [EntityRelation] = []

        for sentence in sentences {
            let entitiesInSentence = entities.filter { entity in
                entity.range.lowerBound >= sentence.range.lowerBound &&
                entity.range.upperBound <= sentence.range.upperBound
            }

            if entitiesInSentence.isEmpty { continue }

            let events = entitiesInSentence.filter { $0.type == .event || $0.type == .activity }
            let persons = entitiesInSentence.filter { $0.type == .person }
            let locations = entitiesInSentence.filter { $0.type == .place }

            if events.isEmpty {
                // Pas d'event explicite mais des entités — créer une relation implicite
                if !persons.isEmpty || !locations.isEmpty {
                    let sentenceText = String(text[sentence.range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    // Titre court : premiers mots significatifs ou lieu/personne
                    let title: String
                    if let loc = locations.first {
                        title = loc.text
                    } else if let person = persons.first {
                        title = "avec \(person.text)"
                    } else {
                        title = String(sentenceText.prefix(40))
                    }

                    relations.append(EntityRelation(
                        event: title,
                        eventType: .activity,
                        persons: persons.map(\.text),
                        locations: locations.map(\.text),
                        description: sentenceText
                    ))
                }
            } else {
                // Lier chaque event aux personnes/lieux de la même phrase
                let sentenceText = String(text[sentence.range]).trimmingCharacters(in: .whitespacesAndNewlines)
                for event in events {
                    relations.append(EntityRelation(
                        event: event.text,
                        eventType: event.type,
                        persons: persons.map(\.text),
                        locations: locations.map(\.text),
                        description: sentenceText
                    ))
                }
            }
        }

        // Log
        print("🔗 Relations extraites:")
        for r in relations {
            let pStr = r.persons.isEmpty ? "—" : r.persons.joined(separator: ", ")
            let lStr = r.locations.isEmpty ? "—" : r.locations.joined(separator: ", ")
            let eventLabel = r.event.count > 40 ? String(r.event.prefix(40)) + "…" : r.event
            print("   \(eventLabel) | lieux: \(lStr) | personnes: \(pStr)")
        }

        return relations
    }

    private struct Sentence {
        let text: String
        let range: Range<String.Index>
    }

    private func splitSentences(_ text: String) -> [Sentence] {
        // D'abord split par ponctuation forte
        var sentences: [Sentence] = []
        var searchStart = text.startIndex
        let delimiters: [Character] = [".", "!", "?", "\n"]

        while searchStart < text.endIndex {
            var sentenceEnd = text.endIndex

            for i in text[searchStart...].indices {
                if delimiters.contains(text[i]) {
                    sentenceEnd = text.index(after: i)
                    break
                }
            }

            let range = searchStart..<sentenceEnd
            let sentenceText = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)

            if !sentenceText.isEmpty {
                sentences.append(Sentence(text: sentenceText, range: range))
            }

            searchStart = sentenceEnd
        }

        // Ensuite, re-split les phrases longues par conjonctions
        var result: [Sentence] = []
        for sentence in sentences {
            if sentence.text.count > 80 {
                let subSentences = splitByConjunctions(String(text[sentence.range]), baseOffset: sentence.range.lowerBound, in: text)
                result.append(contentsOf: subSentences)
            } else {
                result.append(sentence)
            }
        }

        return result.isEmpty ? [Sentence(text: text, range: text.startIndex..<text.endIndex)] : result
    }

    private func splitByConjunctions(_ substring: String, baseOffset: String.Index, in fullText: String) -> [Sentence] {
        let pattern = #"(?:,\s*(?:puis|ensuite|et enfin|enfin|et après|après|et)\s+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return [Sentence(text: substring, range: baseOffset..<fullText.index(baseOffset, offsetBy: substring.count, limitedBy: fullText.endIndex)!)]
        }

        var sentences: [Sentence] = []
        var lastEnd = 0
        let nsRange = NSRange(location: 0, length: substring.utf16.count)

        regex.enumerateMatches(in: substring, range: nsRange) { match, _, _ in
            guard let match, let matchRange = Range(match.range, in: substring) else { return }

            let chunkText = String(substring[substring.index(substring.startIndex, offsetBy: lastEnd)..<matchRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !chunkText.isEmpty {
                let startInFull = fullText.index(baseOffset, offsetBy: lastEnd)
                let endInFull = fullText.index(baseOffset, offsetBy: substring.distance(from: substring.startIndex, to: matchRange.lowerBound))
                sentences.append(Sentence(text: chunkText, range: startInFull..<endInFull))
            }

            lastEnd = substring.distance(from: substring.startIndex, to: matchRange.upperBound)
        }

        // Dernière partie
        if lastEnd < substring.count {
            let chunkText = String(substring[substring.index(substring.startIndex, offsetBy: lastEnd)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunkText.isEmpty {
                let startInFull = fullText.index(baseOffset, offsetBy: lastEnd)
                let endInFull = fullText.index(baseOffset, offsetBy: substring.count, limitedBy: fullText.endIndex) ?? fullText.endIndex
                sentences.append(Sentence(text: chunkText, range: startInFull..<endInFull))
            }
        }

        if sentences.isEmpty {
            let endInFull = fullText.index(baseOffset, offsetBy: substring.count, limitedBy: fullText.endIndex) ?? fullText.endIndex
            sentences.append(Sentence(text: substring, range: baseOffset..<endInFull))
        }

        return sentences
    }
}
