import Foundation
import NaturalLanguage

final class TextCleaner {
    private static let fillers: [String: [String]] = [
        "fr": [
            "euh", "euuuh", "euhh", "heu", "hum", "hmm", "bah", "ben",
            "genre", "tu vois", "tu sais", "voilà", "quoi",
            "en gros", "du coup", "en mode",
        ],
        "en": [
            "um", "uh", "uhh", "umm", "hmm", "hm",
            "like", "you know", "I mean", "basically", "actually",
            "sort of", "kind of",
        ]
    ]

    static func clean(_ text: String) -> String {
        let language = detectLanguage(text)
        let allFillers = fillers[language] ?? fillers["fr"]! + fillers["en"]!

        var result = text

        // Supprimer les fillers isolés (entre virgules, en début de phrase, ou entre points)
        for filler in allFillers.sorted(by: { $0.count > $1.count }) {
            let patterns = [
                ", \(filler), ",       // milieu de phrase
                ", \(filler) ",        // après virgule
                ". \(filler) ",        // début de phrase
                "^\\s*\(filler)\\s+",  // tout début
            ]

            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(result.startIndex..<result.endIndex, in: result)
                    result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: ". ")
                }
            }
        }

        // Nettoyer les espaces/ponctuations en trop
        result = result.replacingOccurrences(of: ".  ", with: ". ")
        result = result.replacingOccurrences(of: ",  ", with: ", ")
        result = result.replacingOccurrences(of: "  ", with: " ")
        result = result.replacingOccurrences(of: ". . ", with: ". ")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        if result != text {
            let removed = text.count - result.count
            print("🧹 TextCleaner: \(removed) caractères nettoyés (\(language))")
        }

        return result
    }

    private static func detectLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage else { return "fr" }
        return lang == .french ? "fr" : lang == .english ? "en" : "fr"
    }
}
