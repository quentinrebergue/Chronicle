import Foundation
import CoreData

final class NarrativeService: @unchecked Sendable {
    private let llmService: LLMService
    private let context: NSManagedObjectContext

    init(llmService: LLMService, context: NSManagedObjectContext) {
        self.llmService = llmService
        self.context = context
    }

    // MARK: - Batch résumés quotidiens (charge le LLM une seule fois)

    func generateBatchDailySummaries(
        for entries: [EntreeVocale],
        progress: @escaping (Int, Int) -> Void
    ) async throws {
        guard !entries.isEmpty else { return }

        AppLogger.log("📖 Batch: \(entries.count) entrées à résumer")
        AppLogger.log("📖 Chargement du LLM…")
        let loadStart = Date()
        try await llmService.loadModel()
        AppLogger.log("📖 LLM chargé en \(String(format: "%.1f", Date().timeIntervalSince(loadStart)))s")

        for (i, entry) in entries.enumerated() {
            progress(i + 1, entries.count)

            let text = entry.transcriptionCorrigee ?? entry.transcriptionBrute ?? ""
            if text.count < 20 {
                AppLogger.log("📖 [\(i + 1)/\(entries.count)] Skip — transcription trop courte (\(text.count) chars)")
                await context.perform {
                    entry.resumeEntree = ""
                    try? self.context.save()
                }
                continue
            }

            let card = StructuredEntryBuilder.buildSummaryCard(for: entry)
            let prompt = NarrativePrompts.dailySummary(card: card)

            AppLogger.log("📖 [\(i + 1)/\(entries.count)] Génération du résumé…")
            AppLogger.log("📖 Input: \(card.prefix(100))…")

            let genStart = Date()
            let summary = try await llmService.generateSummary(prompt: prompt)
            let genTime = Date().timeIntervalSince(genStart)

            AppLogger.log("📖 [\(i + 1)/\(entries.count)] Résumé généré en \(String(format: "%.1f", genTime))s: \(summary.prefix(120))…")

            await context.perform {
                entry.resumeEntree = summary
                try? self.context.save()
            }

            try await generateTitle(for: entry, summary: summary)
        }

        await llmService.unloadModel()
        AppLogger.log("📖 Batch terminé: \(entries.count) résumés générés, LLM déchargé")
    }

    // MARK: - Titre quotidien

    private func generateTitle(for entry: EntreeVocale, summary: String) async throws {
        guard !summary.isEmpty else { return }
        let prompt = NarrativePrompts.dailyTitle(summary: summary)
        let rawTitle = try await llmService.generateSummary(prompt: prompt, maxTokens: 16)
        let title = rawTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\".!?"))

        await context.perform {
            entry.titre = title
            try? self.context.save()
        }
    }

    // MARK: - Résumé quotidien unique

    func generateDailySummary(for entry: EntreeVocale) async throws -> String {
        let card = StructuredEntryBuilder.buildSummaryCard(for: entry)
        let prompt = NarrativePrompts.dailySummary(card: card)

        AppLogger.log("📖 Chargement du LLM pour résumé quotidien…")
        try await llmService.loadModel()
        AppLogger.log("📖 LLM chargé, génération en cours…")

        let genStart = Date()
        let summary = try await llmService.generateSummary(prompt: prompt)
        let genTime = Date().timeIntervalSince(genStart)

        await context.perform {
            entry.resumeEntree = summary
            try? self.context.save()
        }

        try await generateTitle(for: entry, summary: summary)

        await llmService.unloadModel()

        AppLogger.log("📖 Résumé quotidien généré en \(String(format: "%.1f", genTime))s: \(summary.prefix(120))…")
        return summary
    }

    // MARK: - Génération d'un récit dû (chaîne complète, LLM chargé une seule fois)

    func generate(_ due: DueRecit, progress: @escaping @Sendable (String) -> Void) async throws {
        try await llmService.loadModel()
        defer { Task { await self.llmService.unloadModel() } }

        switch due.kind {
        case .weekly(let weekOffset, _, _):
            _ = try await generateWeeklySummary(weekOffset: weekOffset, keepLoaded: true, progress: progress)
        case .monthly(let month, let year):
            _ = try await generateMonthlySummary(month: month, year: year, keepLoaded: true, progress: progress)
        case .yearly(let year):
            _ = try await generateYearlySummary(year: year, keepLoaded: true, progress: progress)
        }
    }

    // MARK: - Résumé hebdomadaire

    func generateWeeklySummary(
        weekOffset: Int = 0,
        keepLoaded: Bool = false,
        progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> String {
        let entries = StructuredEntryBuilder.fetchEntriesForWeek(weekOffset: weekOffset, context: context)
        guard !entries.isEmpty else { throw NarrativeError.noEntries }

        try await llmService.loadModel()

        // Générer d'abord les résumés quotidiens manquants
        let missing = entries.filter {
            ($0.resumeEntree == nil || $0.resumeEntree!.isEmpty)
            && ($0.transcriptionCorrigee ?? $0.transcriptionBrute ?? "").count >= 20
        }
        for (i, entry) in missing.enumerated() {
            progress("Résumé du jour \(i + 1)/\(missing.count)…")
            let card = StructuredEntryBuilder.buildSummaryCard(for: entry)
            let summary = try await llmService.generateSummary(prompt: NarrativePrompts.dailySummary(card: card))
            await context.perform {
                entry.resumeEntree = summary
                try? self.context.save()
            }
            try await generateTitle(for: entry, summary: summary)
        }

        let dailySummaries = entries.compactMap { $0.resumeEntree }.filter { !$0.isEmpty }
        guard !dailySummaries.isEmpty else { throw NarrativeError.noDailySummaries }

        progress("J'organise les faits de la semaine…")
        let facts = StructuredEntryBuilder.buildWeeklyFacts(entries: entries)
        AppLogger.log("📖 Résumé hebdomadaire: \(dailySummaries.count) micro-résumés + faits: \(facts.prefix(120))")

        let prompt = NarrativePrompts.weeklySummary(entries: dailySummaries, facts: facts)

        progress("Écriture du récit de la semaine…")
        let genStart = Date()
        let summary = try await llmService.generateSummary(prompt: prompt, maxTokens: 450)
        let genTime = Date().timeIntervalSince(genStart)
        if !keepLoaded { await llmService.unloadModel() }

        let calendar = Calendar.current
        let refDate = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: Date()) ?? Date()
        let weekNumber = calendar.component(.weekOfYear, from: refDate)
        let year = calendar.component(.yearForWeekOfYear, from: refDate)

        await context.perform {
            let resume = ResumeHebdo(context: self.context)
            resume.id = UUID()
            resume.semaine = Int16(weekNumber)
            resume.annee = Int16(year)
            resume.texteResume = summary
            resume.dateGeneration = Date()
            try? self.context.save()
        }

        AppLogger.log("📖 Résumé hebdomadaire S\(weekNumber) généré en \(String(format: "%.1f", genTime))s: \(summary.prefix(120))…")
        return summary
    }

    // MARK: - Résumé mensuel

    func generateMonthlySummary(
        month: Int,
        year: Int,
        keepLoaded: Bool = false,
        progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> String {
        progress("Chargement du modèle…")
        try await llmService.loadModel()

        let weekSummaries = fetchWeeklySummaries(month: month, year: year)
        guard !weekSummaries.isEmpty else { throw NarrativeError.noWeeklySummaries }

        progress("Je relis tes \(weekSummaries.count) semaines…")
        AppLogger.log("📖 Chapitre mensuel: \(weekSummaries.count) résumés hebdo en entrée")

        let prompt = NarrativePrompts.monthlySummary(weeks: weekSummaries)

        progress("Écriture du chapitre…")
        // 500 mots en français ≈ 800-900 tokens avec ponctuation — 800 coupait la fin, marge portée à 1100.
        let summary = try await llmService.generateSummary(prompt: prompt, maxTokens: 1100)
        if !keepLoaded { await llmService.unloadModel() }

        await context.perform {
            let resume = ResumeMensuel(context: self.context)
            resume.id = UUID()
            resume.mois = Int16(month)
            resume.annee = Int16(year)
            resume.texteResume = summary
            resume.dateGeneration = Date()
            try? self.context.save()
        }

        AppLogger.log("📖 Chapitre mensuel \(month)/\(year) généré: \(summary.prefix(120))…")
        return summary
    }

    // MARK: - Résumé annuel

    func generateYearlySummary(
        year: Int,
        keepLoaded: Bool = false,
        progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> String {
        progress("Chargement du modèle…")
        try await llmService.loadModel()

        let monthlySummaries = fetchMonthlySummaries(year: year)
        guard !monthlySummaries.isEmpty else { throw NarrativeError.noMonthlySummaries }

        progress("Je relis tes \(monthlySummaries.count) mois…")
        let prompt = NarrativePrompts.yearlySummary(months: monthlySummaries)

        progress("Écriture du chapitre de l'année…")
        let summary = try await llmService.generateSummary(prompt: prompt, maxTokens: 2000)
        if !keepLoaded { await llmService.unloadModel() }

        await context.perform {
            let resume = ResumeAnnuel(context: self.context)
            resume.id = UUID()
            resume.annee = Int16(year)
            resume.texteResume = summary
            resume.dateGeneration = Date()
            try? self.context.save()
        }

        AppLogger.log("📖 Chapitre annuel \(year) généré: \(summary.prefix(120))…")
        return summary
    }

    // MARK: - Fetch helpers

    private func fetchWeeklySummaries(month: Int, year: Int) -> [String] {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let monthStart = calendar.date(from: components),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }

        let startWeek = calendar.component(.weekOfYear, from: monthStart)
        let endWeek = calendar.component(.weekOfYear, from: calendar.date(byAdding: .day, value: -1, to: monthEnd)!)

        let request = ResumeHebdo.fetchRequest()
        request.predicate = NSPredicate(
            format: "annee == %d AND semaine >= %d AND semaine <= %d",
            year, startWeek, endWeek
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ResumeHebdo.semaine, ascending: true)]

        let results = (try? context.fetch(request)) ?? []
        return results.compactMap { $0.texteResume }
    }

    private func fetchMonthlySummaries(year: Int) -> [String] {
        let request = ResumeMensuel.fetchRequest()
        request.predicate = NSPredicate(format: "annee == %d", year)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ResumeMensuel.mois, ascending: true)]

        let results = (try? context.fetch(request)) ?? []
        return results.compactMap { $0.texteResume }
    }

    // MARK: - Errors

    enum NarrativeError: Error, LocalizedError {
        case noEntries
        case noDailySummaries
        case noWeeklySummaries
        case noMonthlySummaries

        var errorDescription: String? {
            switch self {
            case .noEntries: return "Aucune entrée pour cette période"
            case .noDailySummaries: return "Les résumés quotidiens n'ont pas encore été générés"
            case .noWeeklySummaries: return "Les résumés hebdomadaires n'ont pas encore été générés"
            case .noMonthlySummaries: return "Les chapitres mensuels n'ont pas encore été générés"
            }
        }
    }
}
