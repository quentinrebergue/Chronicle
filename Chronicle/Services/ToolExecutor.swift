import Foundation
import CoreData

final class ToolExecutor {
    private let viewContext: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.viewContext = context
    }

    func execute(toolCalls: [ChronicleToolCall], for entry: EntreeVocale) throws {
        for call in toolCalls {
            switch call.name {
            case "createPerson":
                try createPerson(args: call.arguments, entry: entry)
            case "createEvent":
                try createEvent(args: call.arguments, entry: entry)
            case "createPlace":
                try createPlace(args: call.arguments)
            case "setEmotion":
                setEmotion(args: call.arguments, entry: entry)
            default:
                break
            }
        }
        try viewContext.save()
    }

    func fetchKnownEntities() -> KnownEntities {
        var entities = KnownEntities()

        let personRequest = Personne.fetchRequest()
        if let personnes = try? viewContext.fetch(personRequest) {
            entities.personnes = personnes.compactMap { $0.nom }
        }

        let lieuRequest = Lieu.fetchRequest()
        if let lieux = try? viewContext.fetch(lieuRequest) {
            entities.lieux = lieux.compactMap { $0.nom }
        }

        let themeRequest = Theme.fetchRequest()
        if let themes = try? viewContext.fetch(themeRequest) {
            entities.themes = themes.compactMap { $0.label }
        }

        return entities
    }

    private func createPerson(args: [String: String], entry: EntreeVocale) throws {
        guard let name = args["name"] else { return }

        let request = Personne.fetchRequest()
        request.predicate = NSPredicate(format: "nom ==[cd] %@", name)

        let existing = try viewContext.fetch(request).first

        let person = existing ?? Personne(context: viewContext)
        if existing == nil {
            person.id = UUID()
            person.nom = name
            person.frequenceMention = 0
        }

        person.frequenceMention += 1
        person.derniereApparition = Date()
        if let relation = args["relation"] { person.relation = relation }
        if let sentiment = args["sentiment"] { person.sentimentMoyen = sentiment }

        entry.addToPersonnes(person)
    }

    private func createEvent(args: [String: String], entry: EntreeVocale) throws {
        guard let title = args["title"] else { return }

        let event = Evenement(context: viewContext)
        event.id = UUID()
        event.titre = title
        event.emotion = args["emotion"]
        event.lieu = args["lieu"]

        if let importanceStr = args["importance"], let importance = Int16(importanceStr) {
            event.importance = importance
        }

        if let dateStr = args["date"] {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            event.dateEvenement = formatter.date(from: dateStr)
        }

        entry.addToEvenements(event)
    }

    private func createPlace(args: [String: String]) throws {
        guard let name = args["name"] else { return }

        let request = Lieu.fetchRequest()
        request.predicate = NSPredicate(format: "nom ==[cd] %@", name)

        if let existing = try viewContext.fetch(request).first {
            existing.frequence += 1
            if let context = args["context"] { existing.contexte = context }
        } else {
            let lieu = Lieu(context: viewContext)
            lieu.id = UUID()
            lieu.nom = name
            lieu.contexte = args["context"]
            lieu.frequence = 1
        }
    }

    private func setEmotion(args: [String: String], entry: EntreeVocale) {
        entry.emotionDominante = args["emotion"]
        if let intensityStr = args["intensity"], let intensity = Int16(intensityStr) {
            entry.intensiteEmotion = intensity
        }
    }
}
