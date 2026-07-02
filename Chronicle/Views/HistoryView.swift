import SwiftUI
import CoreData

/// L'Autobiographie — uniquement les récits générés (hebdo, mensuels, annuels).
/// Les entrées journalières brutes vivent dans JournalView.
struct HistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var llmService: LLMService
    var onMenuTap: () -> Void

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ResumeHebdo.annee, ascending: false),
            NSSortDescriptor(keyPath: \ResumeHebdo.semaine, ascending: false)
        ],
        animation: .default
    )
    private var weeklyResumes: FetchedResults<ResumeHebdo>

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ResumeMensuel.annee, ascending: false),
            NSSortDescriptor(keyPath: \ResumeMensuel.mois, ascending: false)
        ],
        animation: .default
    )
    private var monthlyResumes: FetchedResults<ResumeMensuel>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ResumeAnnuel.annee, ascending: false)],
        animation: .default
    )
    private var yearlyResumes: FetchedResults<ResumeAnnuel>

    @State private var dueRecits: [DueRecit] = []
    @State private var generatingDue: DueRecit?
    @State private var generationStatus = ""
    @State private var readerData: RecitReaderData?

    var body: some View {
        VStack(spacing: 0) {
            OtobioTopBar(title: "Autobiographie", onMenuTap: onMenuTap)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    dueSection

                    // Le récit en cours d'écriture apparaît immédiatement en skeleton,
                    // déjà sous son vrai titre ("Semaine du ... au ...") plutôt qu'un texte d'accroche.
                    if let due = generatingDue {
                        skeletonRecitCard(title: RecitPlanner.periodTitle(for: due.kind), status: generationStatus)
                    }

                    if recitGroups.isEmpty {
                        if generatingDue == nil { emptyState }
                    } else {
                        flowSections
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .background(Otobio.background.ignoresSafeArea())
        .onAppear { refreshDue() }
        .fullScreenCover(item: $readerData) { data in
            RecitReaderView(data: data)
        }
    }

    private func refreshDue() {
        dueRecits = RecitPlanner.dueRecits(context: viewContext)
    }

    // MARK: - Récits à écrire (rangées compactes, style notifications)

    /// Les récits dus, sans celui déjà en cours d'écriture (il a sa propre carte plus bas).
    private var pendingDueRecits: [DueRecit] {
        dueRecits.filter { $0.id != generatingDue?.id }
    }

    @ViewBuilder
    private var dueSection: some View {
        if !pendingDueRecits.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("À écrire")
                    .font(Otobio.uiTitle(15))
                    .foregroundStyle(Otobio.textSecondary)

                VStack(spacing: 6) {
                    ForEach(pendingDueRecits) { due in
                        DueRecitRow(
                            due: due,
                            isGenerating: false,
                            status: "",
                            disabled: generatingDue != nil
                        ) {
                            generate(due)
                        }
                    }
                }
            }
        }
    }

    private func generate(_ due: DueRecit) {
        generatingDue = due
        generationStatus = "Chargement du modèle…"
        Task {
            do {
                let service = NarrativeService(llmService: llmService, context: viewContext)
                try await service.generate(due) { status in
                    Task { @MainActor in generationStatus = status }
                }
            } catch {
                AppLogger.log("⚠️ Génération récit: \(error)")
            }
            generatingDue = nil
            generationStatus = ""
            refreshDue()
        }
    }

    // MARK: - Flux des récits

    private enum RecitItem: Identifiable {
        case weekly(ResumeHebdo)
        case monthly(ResumeMensuel)
        case yearly(ResumeAnnuel)

        var id: NSManagedObjectID {
            switch self {
            case .weekly(let r): r.objectID
            case .monthly(let r): r.objectID
            case .yearly(let r): r.objectID
            }
        }

        /// Un récit résume une période : il se place à la FIN de celle-ci.
        var sortDate: Date {
            let calendar = Calendar.current
            switch self {
            case .weekly(let r):
                var c = DateComponents()
                c.weekOfYear = Int(r.semaine)
                c.yearForWeekOfYear = Int(r.annee)
                guard let start = calendar.date(from: c) else { return .distantPast }
                return calendar.date(byAdding: DateComponents(day: 7, second: -1), to: start) ?? start
            case .monthly(let r):
                var c = DateComponents()
                c.year = Int(r.annee)
                c.month = Int(r.mois)
                c.day = 1
                guard let start = calendar.date(from: c) else { return .distantPast }
                return calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
            case .yearly(let r):
                var c = DateComponents()
                c.year = Int(r.annee) + 1
                c.month = 1
                c.day = 1
                guard let nextYear = calendar.date(from: c) else { return .distantPast }
                return nextYear.addingTimeInterval(-1)
            }
        }

        /// À date égale, le récit le plus large passe au-dessus (année > mois > semaine).
        var rank: Int {
            switch self {
            case .weekly: 1
            case .monthly: 2
            case .yearly: 3
            }
        }
    }

    private struct RecitGroup: Identifiable {
        let id: String
        let label: String
        var items: [RecitItem]
    }

    private var recitGroups: [RecitGroup] {
        var items: [RecitItem] = []
        items.append(contentsOf: weeklyResumes.map { .weekly($0) })
        items.append(contentsOf: monthlyResumes.map { .monthly($0) })
        items.append(contentsOf: yearlyResumes.map { .yearly($0) })

        let sorted = items.sorted {
            $0.sortDate != $1.sortDate ? $0.sortDate > $1.sortDate : $0.rank > $1.rank
        }

        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr-FR")
        formatter.dateFormat = "MMMM yyyy"

        var groups: [RecitGroup] = []
        var currentKey = ""
        for item in sorted {
            let comps = calendar.dateComponents([.year, .month], from: item.sortDate)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            if key != currentKey {
                groups.append(RecitGroup(
                    id: key,
                    label: formatter.string(from: item.sortDate).capitalized,
                    items: []
                ))
                currentKey = key
            }
            groups[groups.count - 1].items.append(item)
        }
        return groups
    }

    private var flowSections: some View {
        ForEach(recitGroups) { group in
            VStack(alignment: .leading, spacing: 12) {
                Text(group.label)
                    .font(Otobio.uiTitle(16))
                    .foregroundStyle(Otobio.textPrimary)

                ForEach(group.items) { item in
                    itemView(item)
                }
            }
        }
    }

    @ViewBuilder
    private func itemView(_ item: RecitItem) -> some View {
        switch item {
        case .weekly(let resume):
            recitRow(
                title: weekTitle(resume),
                icon: "book.pages",
                text: resume.texteResume ?? "",
                date: resume.dateGeneration
            ) {
                delete(resume)
            }
        case .monthly(let resume):
            recitRow(
                title: monthTitle(resume),
                icon: "book.closed",
                text: resume.texteResume ?? "",
                date: resume.dateGeneration
            ) {
                delete(resume)
            }
        case .yearly(let resume):
            recitRow(
                title: "L'année \(resume.annee)",
                icon: "books.vertical",
                text: resume.texteResume ?? "",
                date: resume.dateGeneration
            ) {
                delete(resume)
            }
        }
    }

    private func recitRow(
        title: String,
        icon: String,
        text: String,
        date: Date?,
        onDelete: @escaping () -> Void
    ) -> some View {
        SwipeToDeleteRow {
            RecitRowCard(title: title, icon: icon, preview: text) {
                readerData = RecitReaderData(title: title, date: date, text: text)
            }
        } onDelete: {
            onDelete()
        }
    }

    /// La carte du récit en cours d'écriture — le contenu arrive, sa place est déjà là.
    /// Le squelette montre OÙ ; la phrase qui tourne montre QUE ça avance.
    private func skeletonRecitCard(title: String, status: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "book.pages")
                    .font(.system(size: 13))
                    .foregroundStyle(Otobio.brand)
                Text(title)
                    .font(Otobio.uiTitle(15))
                    .foregroundStyle(Otobio.textPrimary)
                    .lineLimit(1)
                Spacer()
            }

            SkeletonBar(height: 11)
            SkeletonBar(height: 11)
            SkeletonBar(width: 180, height: 11)

            RotatingStatusText(phrases: GenerationPhrase.forStatus(status))
                .padding(.top, 2)
        }
        .otobioCard(background: Otobio.recitCardBackground)
    }

    // MARK: - Titres

    private func weekTitle(_ resume: ResumeHebdo) -> String {
        var components = DateComponents()
        components.weekOfYear = Int(resume.semaine)
        components.yearForWeekOfYear = Int(resume.annee)
        let calendar = Calendar.current
        guard let weekStart = calendar.date(from: components),
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return "Semaine \(resume.semaine)"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr-FR")
        formatter.dateFormat = "d MMMM"
        return "Semaine du \(formatter.string(from: weekStart)) au \(formatter.string(from: weekEnd))"
    }

    private func monthTitle(_ resume: ResumeMensuel) -> String {
        var components = DateComponents()
        components.year = Int(resume.annee)
        components.month = Int(resume.mois)
        components.day = 1
        guard let date = Calendar.current.date(from: components) else {
            return "Mois \(resume.mois)/\(resume.annee)"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr-FR")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).capitalized
    }

    // MARK: - État vide

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "book")
                .font(.system(size: 30))
                .foregroundStyle(Otobio.textTertiary)
            Text("Ton autobiographie est encore vide")
                .font(Otobio.uiTitle(16))
                .foregroundStyle(Otobio.textSecondary)
            Text("Les récits s'écriront au fil de tes semaines.\nTes entrées quotidiennes vivent dans le Journal.")
                .font(Otobio.label())
                .foregroundStyle(Otobio.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    // MARK: - Suppression

    private func delete(_ resume: ResumeHebdo) {
        viewContext.delete(resume)
        try? viewContext.save()
    }

    private func delete(_ resume: ResumeMensuel) {
        viewContext.delete(resume)
        try? viewContext.save()
    }

    private func delete(_ resume: ResumeAnnuel) {
        viewContext.delete(resume)
        try? viewContext.save()
    }
}

// MARK: - Ligne avec swipe-to-delete (style Apple)

/// Enveloppe un contenu avec un geste de swipe vers la gauche révélant une zone
/// "Supprimer" rouge (style Apple) — taper dessus supprime directement, sans popup.
struct SwipeToDeleteRow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0

    private let deleteWidth: CGFloat = 88

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { offset = 0 }
                dragStartOffset = 0
                onDelete()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Supprimer")
                        .font(Otobio.micro())
                }
                .foregroundStyle(Otobio.onDestructive)
                .frame(width: deleteWidth)
                .frame(maxHeight: .infinity)
            }
            .background(Otobio.destructive)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            content()
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            let isMostlyHorizontal = abs(value.translation.width) > abs(value.translation.height) * 2
                            guard isMostlyHorizontal else { return }
                            offset = max(-deleteWidth, min(0, dragStartOffset + value.translation.width))
                        }
                        .onEnded { value in
                            let shouldOpen = offset < -deleteWidth / 2
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                offset = shouldOpen ? -deleteWidth : 0
                            }
                            dragStartOffset = shouldOpen ? -deleteWidth : 0
                        }
                )
        }
    }
}

// MARK: - Rangée "récit à écrire" (compacte, style notification)

struct DueRecitRow: View {
    let due: DueRecit
    let isGenerating: Bool
    let status: String
    let disabled: Bool
    let onGenerate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Otobio.brand)
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(Otobio.background)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(due.title)
                    .font(Otobio.uiTitle(14))
                    .foregroundStyle(Otobio.textPrimary)
                    .lineLimit(1)
                if isGenerating {
                    RotatingStatusText(phrases: GenerationPhrase.forStatus(status))
                } else {
                    Text(due.subtitle)
                        .font(Otobio.micro())
                        .foregroundStyle(Otobio.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isGenerating {
                ProgressView()
                    .tint(Otobio.brand)
                    .scaleEffect(0.8)
            } else {
                Button(action: onGenerate) {
                    Text("Écrire")
                        .font(Otobio.label(13))
                        .foregroundStyle(Otobio.background)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Otobio.brand)
                        .clipShape(Capsule())
                }
                .disabled(disabled)
                .opacity(disabled ? 0.5 : 1)
            }
        }
        .padding(12)
        .background(Otobio.recitCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Otobio.cardShadow, radius: 8, x: 0, y: 3)
    }
}

// MARK: - Carte de récit (compacte, ouvre la page de lecture)

struct RecitRowCard: View {
    let title: String
    let icon: String
    let preview: String
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Otobio.brand)
                Text(title)
                    .font(Otobio.uiTitle(15))
                    .foregroundStyle(Otobio.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Otobio.textTertiary)
            }

            Text(preview)
                .font(Otobio.serifBody(14))
                .foregroundStyle(Otobio.textSecondary)
                .lineLimit(2)
                .lineSpacing(3)
        }
        .otobioCard(background: Otobio.recitCardBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}
