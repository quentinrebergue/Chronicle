import Foundation
import CoreData

/// Un récit qui devrait exister mais n'a pas encore été généré.
struct DueRecit: Identifiable, Equatable {
    enum Kind: Equatable {
        case weekly(weekOffset: Int, week: Int, year: Int)
        case monthly(month: Int, year: Int)
        case yearly(year: Int)
    }

    let kind: Kind
    let title: String
    let subtitle: String

    var id: String {
        switch kind {
        case .weekly(_, let week, let year): return "weekly-\(year)-\(week)"
        case .monthly(let month, let year): return "monthly-\(year)-\(month)"
        case .yearly(let year): return "yearly-\(year)"
        }
    }
}

/// Détermine quels récits sont dus : une période terminée, avec du contenu,
/// mais dont le récit n'a pas encore été généré.
enum RecitPlanner {
    /// Nombre de semaines/mois passés à scanner (au-delà, on considère l'occasion manquée)
    private static let weeklyLookback = 8
    private static let monthlyLookback = 6

    static func dueRecits(context: NSManagedObjectContext) -> [DueRecit] {
        var due: [DueRecit] = []
        due.append(contentsOf: dueWeeklies(context: context))
        due.append(contentsOf: dueMonthlies(context: context))
        due.append(contentsOf: dueYearlies(context: context))
        return due
    }

    // MARK: - Hebdo

    private static func dueWeeklies(context: NSManagedObjectContext) -> [DueRecit] {
        let calendar = Calendar.current
        var due: [DueRecit] = []

        for offset in 1...weeklyLookback {
            guard let refDate = calendar.date(byAdding: .weekOfYear, value: -offset, to: Date()) else { continue }
            let week = calendar.component(.weekOfYear, from: refDate)
            let year = calendar.component(.yearForWeekOfYear, from: refDate)

            guard !weeklyExists(week: week, year: year, context: context) else { continue }

            let entries = StructuredEntryBuilder.fetchEntriesForWeek(weekOffset: offset, context: context)
            guard !entries.isEmpty else { continue }

            let interval = calendar.dateInterval(of: .weekOfYear, for: refDate)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "fr-FR")
            formatter.dateFormat = "d MMMM"
            let range: String
            if let interval {
                let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
                range = "\(formatter.string(from: interval.start)) – \(formatter.string(from: end))"
            } else {
                range = "Semaine \(week)"
            }

            due.append(DueRecit(
                kind: .weekly(weekOffset: offset, week: week, year: year),
                title: "Ton récit de la semaine t'attend",
                subtitle: "\(range) · \(entries.count) entrée\(entries.count > 1 ? "s" : "")"
            ))
        }
        return due
    }

    private static func weeklyExists(week: Int, year: Int, context: NSManagedObjectContext) -> Bool {
        let request = ResumeHebdo.fetchRequest()
        request.predicate = NSPredicate(format: "semaine == %d AND annee == %d", week, year)
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }

    // MARK: - Mensuel

    private static func dueMonthlies(context: NSManagedObjectContext) -> [DueRecit] {
        let calendar = Calendar.current
        var due: [DueRecit] = []

        for offset in 1...monthlyLookback {
            guard let refDate = calendar.date(byAdding: .month, value: -offset, to: Date()) else { continue }
            let month = calendar.component(.month, from: refDate)
            let year = calendar.component(.year, from: refDate)

            guard !monthlyExists(month: month, year: year, context: context) else { continue }
            guard hasWeeklies(month: month, year: year, context: context) else { continue }

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "fr-FR")
            formatter.dateFormat = "MMMM yyyy"

            due.append(DueRecit(
                kind: .monthly(month: month, year: year),
                title: "Un nouveau chapitre à écrire",
                subtitle: formatter.string(from: refDate).capitalized
            ))
        }
        return due
    }

    private static func monthlyExists(month: Int, year: Int, context: NSManagedObjectContext) -> Bool {
        let request = ResumeMensuel.fetchRequest()
        request.predicate = NSPredicate(format: "mois == %d AND annee == %d", month, year)
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }

    private static func hasWeeklies(month: Int, year: Int, context: NSManagedObjectContext) -> Bool {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let monthStart = calendar.date(from: components),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return false }
        let startWeek = calendar.component(.weekOfYear, from: monthStart)
        let endWeek = calendar.component(.weekOfYear, from: calendar.date(byAdding: .day, value: -1, to: monthEnd)!)

        let request = ResumeHebdo.fetchRequest()
        request.predicate = NSPredicate(format: "annee == %d AND semaine >= %d AND semaine <= %d", year, startWeek, endWeek)
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }

    // MARK: - Annuel

    private static func dueYearlies(context: NSManagedObjectContext) -> [DueRecit] {
        let calendar = Calendar.current
        let lastYear = calendar.component(.year, from: Date()) - 1

        let existsRequest = ResumeAnnuel.fetchRequest()
        existsRequest.predicate = NSPredicate(format: "annee == %d", lastYear)
        existsRequest.fetchLimit = 1
        guard ((try? context.count(for: existsRequest)) ?? 0) == 0 else { return [] }

        let monthliesRequest = ResumeMensuel.fetchRequest()
        monthliesRequest.predicate = NSPredicate(format: "annee == %d", lastYear)
        monthliesRequest.fetchLimit = 1
        guard ((try? context.count(for: monthliesRequest)) ?? 0) > 0 else { return [] }

        return [DueRecit(
            kind: .yearly(year: lastYear),
            title: "Une année de ta vie, racontée",
            subtitle: "L'année \(lastYear)"
        )]
    }

    // MARK: - Titre définitif de la période

    /// Le vrai titre de la période visée (ex. "Semaine du 12 au 18 janvier"),
    /// utilisé pendant la génération pour que la carte squelette annonce déjà ce qu'elle contiendra.
    static func periodTitle(for kind: DueRecit.Kind) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr-FR")

        switch kind {
        case .weekly(_, let week, let year):
            var components = DateComponents()
            components.weekOfYear = week
            components.yearForWeekOfYear = year
            guard let weekStart = calendar.date(from: components),
                  let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
                return "Semaine \(week)"
            }
            formatter.dateFormat = "d MMMM"
            return "Semaine du \(formatter.string(from: weekStart)) au \(formatter.string(from: weekEnd))"

        case .monthly(let month, let year):
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            guard let date = calendar.date(from: components) else {
                return "Mois \(month)/\(year)"
            }
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date).capitalized

        case .yearly(let year):
            return "L'année \(year)"
        }
    }
}
