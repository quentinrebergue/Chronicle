#if DEBUG
import SwiftUI
import CoreData

/// Écran de développement — génère de fausses entrées avec des dates rétroactives
/// pour tester rapidement les récits hebdomadaires / mensuels / annuels sans attendre des semaines.
/// N'est jamais compilé en build Release.
struct DebugSeedView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var weeksBack: Double = 3
    @State private var entriesPerWeek: Double = 4
    @State private var extractEntities = true
    @State private var isSeeding = false
    @State private var status = ""
    @State private var seededCount = 0

    private static let marker = "debug-seed-"

    private static let sampleTexts: [String] = [
        "Aujourd'hui j'ai retrouvé Marie au café République pour discuter du projet. On a parlé pendant deux heures, c'était vraiment agréable. Ensuite je suis rentré à pied, il faisait beau.",
        "Grosse journée de travail. J'ai eu une présentation importante avec Étienne, ça s'est plutôt bien passé même si j'étais stressé. Le soir j'ai fait un trail à Howth pour décompresser.",
        "Journée calme, je suis resté à la maison. J'ai appelé mes parents, ma mère m'a raconté sa semaine. Un peu de lecture avant de dormir.",
        "On a fêté l'anniversaire de Julie ce soir, il y avait beaucoup de monde. Martin était là aussi, ça faisait longtemps qu'on ne s'était pas vus. Super soirée.",
        "Réunion difficile au bureau avec Sophie, on n'était pas d'accord sur la direction du projet. J'ai fini par céder mais je ne suis pas convaincu. Besoin de recul.",
        "Dimanche tranquille à Dublin. Je suis allé courir le long de la mer, il y avait du vent. L'après-midi j'ai rangé l'appartement et préparé la semaine.",
        "J'ai eu un appel avec Nicolas pour parler de son déménagement à Cork. Il a l'air content de ce changement. On a prévu de se voir avant son départ.",
        "Petit coup de mou aujourd'hui, la fatigue s'accumule. J'ai quand même réussi à avancer sur mes dossiers. Vivement le week-end pour souffler un peu."
    ]

    /// Titres bref alignés sur sampleTexts (même index), à défaut de faire tourner le LLM pour chaque entrée de test.
    private static let sampleTitles: [String] = [
        "Café avec Marie",
        "Présentation et trail à Howth",
        "Journée calme à la maison",
        "Anniversaire de Julie",
        "Réunion difficile",
        "Dimanche à Dublin",
        "Appel avec Nicolas",
        "Coup de mou"
    ]

    var body: some View {
        Form {
            Section {
                Stepper("Semaines en arrière : \(Int(weeksBack))", value: $weeksBack, in: 1...12)
                Stepper("Entrées par semaine : \(Int(entriesPerWeek))", value: $entriesPerWeek, in: 1...7)
                Toggle("Extraire les entités (personnes, lieux)", isOn: $extractEntities)
            } header: {
                Text("Génération")
            } footer: {
                Text("Crée \(Int(weeksBack) * Int(entriesPerWeek)) fausses entrées réparties sur les \(Int(weeksBack)) dernières semaines, avec dateEnregistrement rétroactive. Les résumés quotidiens ne sont PAS générés — utilise le bouton \"Résumer\" habituel ou les cartes de la Bibliothèque après.")
            }

            Section {
                Button {
                    seed()
                } label: {
                    if isSeeding {
                        HStack {
                            ProgressView()
                            Text(status)
                        }
                    } else {
                        Text("Générer")
                    }
                }
                .disabled(isSeeding)
            }

            Section {
                Button(role: .destructive) {
                    deleteSeeded()
                } label: {
                    Text("Supprimer les entrées générées")
                }
                .disabled(isSeeding)
            } footer: {
                Text("Supprime uniquement les entrées créées par cet écran (marquées debug-seed).")
            }

            if seededCount > 0 {
                Section {
                    Text("\(seededCount) entrée(s) générée(s) au total dans cette session.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Injecter du contenu")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func seed() {
        isSeeding = true
        status = "Préparation…"

        Task {
            let calendar = Calendar.current
            let gliner = GLiNERService()
            let relationExtractor = RelationExtractor()
            let toolExecutor = ToolExecutor(context: viewContext)
            let nlpService = NLPService()

            if extractEntities {
                status = "Chargement de GLiNER…"
                try? await gliner.load()
            }

            var created = 0
            let totalWeeks = Int(weeksBack)
            let perWeek = Int(entriesPerWeek)

            for week in 0..<totalWeeks {
                guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -week, to: Date()) else { continue }

                for i in 0..<perWeek {
                    let dayOffset = Int.random(in: 0...6)
                    let hour = Int.random(in: 18...21)
                    guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: weekStart),
                          let date = calendar.date(bySettingHour: hour, minute: Int.random(in: 0...59), second: 0, of: day) else { continue }

                    let sampleIndex = Int.random(in: 0..<Self.sampleTexts.count)
                    let text = Self.sampleTexts[sampleIndex]
                    let title = Self.sampleTitles[sampleIndex]

                    await MainActor.run {
                        status = "Semaine \(week + 1)/\(totalWeeks), entrée \(i + 1)/\(perWeek)…"
                    }

                    let entry = EntreeVocale(context: viewContext)
                    entry.id = UUID()
                    entry.dateEnregistrement = date
                    entry.dureeSecondes = Double.random(in: 30...110)
                    entry.transcriptionBrute = text
                    entry.titre = title
                    entry.cheminAudio = "\(Self.marker)\(entry.id?.uuidString ?? UUID().uuidString)"
                    try? viewContext.save()

                    if extractEntities {
                        let glinerEntities = (try? gliner.extractEntities(from: text)) ?? []
                        let detected: [DetectedEntity] = glinerEntities.compactMap { entity in
                            let startIdx = text.index(text.startIndex, offsetBy: entity.startIdx, limitedBy: text.endIndex) ?? text.startIndex
                            let endIdx = text.index(text.startIndex, offsetBy: entity.endIdx, limitedBy: text.endIndex) ?? text.endIndex
                            let type: DetectedEntity.EntityType = switch entity.label {
                            case "person": .person
                            case "location": .place
                            case "event": .event
                            case "activity": .activity
                            default: .organization
                            }
                            return DetectedEntity(text: entity.text, type: type, range: startIdx..<endIdx)
                        }

                        var merged = detected
                        for nlpEntity in nlpService.detectEntities(in: text) {
                            if !merged.contains(where: { $0.range.overlaps(nlpEntity.range) }) {
                                merged.append(nlpEntity)
                            }
                        }

                        try? toolExecutor.createEntitiesFromNLP(
                            detected: merged.filter { $0.type == .person || $0.type == .place },
                            existing: [],
                            for: entry
                        )

                        let relations = relationExtractor.extractRelations(from: text, entities: merged)
                        if !relations.isEmpty {
                            try? toolExecutor.createStructuredEvents(from: relations, for: entry)
                        }
                    }

                    created += 1
                }
            }

            if extractEntities {
                gliner.unload()
            }

            await MainActor.run {
                seededCount += created
                status = ""
                isSeeding = false
            }
        }
    }

    private func deleteSeeded() {
        let request = EntreeVocale.fetchRequest()
        request.predicate = NSPredicate(format: "cheminAudio BEGINSWITH %@", Self.marker)
        if let results = try? viewContext.fetch(request) {
            for entry in results {
                viewContext.delete(entry)
            }
            try? viewContext.save()
            seededCount = 0
        }
    }
}
#endif
