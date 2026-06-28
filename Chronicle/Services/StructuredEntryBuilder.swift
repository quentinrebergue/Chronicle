import Foundation
import CoreData

final class StructuredEntryBuilder {
    static func buildSummaryCard(for entry: EntreeVocale) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr-FR")
        formatter.dateFormat = "EEEE d MMMM yyyy, HH'h'mm"

        var card = "Date: \(formatter.string(from: entry.dateEnregistrement ?? Date()))\n"

        // Événements avec personnes et lieux
        let events = (entry.evenements as? Set<Evenement>) ?? []
        if !events.isEmpty {
            card += "Événements:\n"
            for event in events.sorted(by: { ($0.dateEvenement ?? Date()) < ($1.dateEvenement ?? Date()) }) {
                var line = "- \(event.titre ?? "?")"

                if let lieu = event.lieu, !lieu.isEmpty {
                    line += " à \(lieu)"
                }

                let personnes = (event.personnes as? Set<Personne>) ?? []
                if !personnes.isEmpty {
                    let noms = personnes.compactMap(\.nom).joined(separator: ", ")
                    line += " avec \(noms)"
                }

                card += "\(line)\n"
            }
        }

        // Texte source
        let texte = entry.transcriptionCorrigee ?? entry.transcriptionBrute ?? ""
        if !texte.isEmpty {
            card += "Texte: \(texte)\n"
        }

        return card
    }

    static func buildWeeklySummaryInput(entries: [EntreeVocale]) -> String {
        var result = ""
        for (i, entry) in entries.enumerated() {
            result += "--- Jour \(i + 1) ---\n"
            result += buildSummaryCard(for: entry)
            result += "\n"
        }
        return result
    }

    static func fetchEntriesForWeek(weekOffset: Int = 0, context: NSManagedObjectContext) -> [EntreeVocale] {
        let calendar = Calendar.current
        let now = Date()

        guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: calendar.startOfDay(for: now)),
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return []
        }

        let request = EntreeVocale.fetchRequest()
        request.predicate = NSPredicate(format: "dateEnregistrement >= %@ AND dateEnregistrement < %@", weekStart as NSDate, weekEnd as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EntreeVocale.dateEnregistrement, ascending: true)]

        return (try? context.fetch(request)) ?? []
    }
}
