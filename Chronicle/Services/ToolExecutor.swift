import Foundation
import CoreData

final class ToolExecutor {
    private let viewContext: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.viewContext = context
    }

    func createEntitiesFromNLP(detected: [DetectedEntity], existing: Set<String>, for entry: EntreeVocale) throws {
        for entity in detected {
            if existing.contains(entity.text) {
                // Entité connue — juste lier et incrémenter
                switch entity.type {
                case .person:
                    try linkExistingPerson(name: entity.text, entry: entry)
                case .place:
                    try linkExistingPlace(name: entity.text)
                case .event, .activity:
                    try linkExistingEvent(name: entity.text, entry: entry)
                case .organization:
                    break
                }
            } else {
                // Nouvelle entité
                switch entity.type {
                case .person:
                    try createPerson(args: ["name": entity.text], entry: entry)
                case .place:
                    try createPlace(args: ["name": entity.text])
                case .event, .activity:
                    try createEvent(args: ["title": entity.text], entry: entry)
                case .organization:
                    break
                }
            }
        }
        try viewContext.save()
        print("💾 Entités NLP sauvegardées: \(detected.map { "[\($0.type.rawValue):\($0.text)]" })")
    }

    func createStructuredEvents(from relations: [EntityRelation], for entry: EntreeVocale) throws {
        for relation in relations {
            let event = Evenement(context: viewContext)
            event.id = UUID()
            event.titre = relation.event
            event.dateEvenement = entry.dateEnregistrement
            event.lieu = relation.locations.first
            event.descriptionTexte = relation.event

            // Lier les personnes
            for personName in relation.persons {
                let request = Personne.fetchRequest()
                request.predicate = NSPredicate(format: "nom ==[cd] %@", personName)
                if let person = try viewContext.fetch(request).first {
                    event.addToPersonnes(person)
                }
            }

            entry.addToEvenements(event)
        }

        try viewContext.save()
        print("💾 Événements structurés créés: \(relations.count)")
        for r in relations {
            let p = r.persons.isEmpty ? "—" : r.persons.joined(separator: ", ")
            let l = r.locations.isEmpty ? "—" : r.locations.joined(separator: ", ")
            print("   📌 \(r.event) | \(l) | \(p)")
        }
    }

    private func linkExistingEvent(name: String, entry: EntreeVocale) throws {
        let request = Evenement.fetchRequest()
        request.predicate = NSPredicate(format: "titre ==[cd] %@", name)
        guard let event = try viewContext.fetch(request).first else { return }
        entry.addToEvenements(event)
    }

    private func linkExistingPerson(name: String, entry: EntreeVocale) throws {
        let request = Personne.fetchRequest()
        request.predicate = NSPredicate(format: "nom ==[cd] %@", name)
        guard let person = try viewContext.fetch(request).first else { return }
        person.frequenceMention += 1
        person.derniereApparition = Date()
        entry.addToPersonnes(person)
    }

    private func linkExistingPlace(name: String) throws {
        let request = Lieu.fetchRequest()
        request.predicate = NSPredicate(format: "nom ==[cd] %@", name)
        guard let lieu = try viewContext.fetch(request).first else { return }
        lieu.frequence += 1
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
