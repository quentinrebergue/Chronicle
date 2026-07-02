import SwiftUI
import CoreData

/// Le Journal — les entrées quotidiennes brutes, groupées par mois.
/// L'Autobiographie (récits générés) vit dans HistoryView.
struct JournalView: View {
    @Environment(\.managedObjectContext) private var viewContext
    var onMenuTap: () -> Void

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \EntreeVocale.dateEnregistrement, ascending: false)],
        animation: .default
    )
    private var entries: FetchedResults<EntreeVocale>

    @State private var selectedEntry: EntreeVocale?

    var body: some View {
        VStack(spacing: 0) {
            OtobioTopBar(title: "Journal", onMenuTap: onMenuTap)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if monthGroups.isEmpty {
                        emptyState
                    } else {
                        ForEach(monthGroups) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(group.label)
                                    .font(Otobio.uiTitle(16))
                                    .foregroundStyle(Otobio.textPrimary)

                                ForEach(group.entries, id: \.objectID) { entry in
                                    SwipeToDeleteRow {
                                        EntryCard(entry: entry)
                                            .onTapGesture { selectedEntry = entry }
                                    } onDelete: {
                                        delete(entry)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .background(Otobio.background.ignoresSafeArea())
        .fullScreenCover(item: $selectedEntry) { entry in
            EntryDetailView(entry: entry)
                .environment(\.managedObjectContext, viewContext)
        }
    }

    // MARK: - Groupes par mois

    private struct MonthGroup: Identifiable {
        let id: String
        let label: String
        var entries: [EntreeVocale]
    }

    private var monthGroups: [MonthGroup] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr-FR")
        formatter.dateFormat = "MMMM yyyy"

        var groups: [MonthGroup] = []
        var currentKey = ""
        for entry in entries {
            let date = entry.dateEnregistrement ?? .distantPast
            let comps = calendar.dateComponents([.year, .month], from: date)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            if key != currentKey {
                groups.append(MonthGroup(
                    id: key,
                    label: formatter.string(from: date).capitalized,
                    entries: []
                ))
                currentKey = key
            }
            groups[groups.count - 1].entries.append(entry)
        }
        return groups
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "mic")
                .font(.system(size: 30))
                .foregroundStyle(Otobio.textTertiary)
            Text("Aucune entrée pour l'instant")
                .font(Otobio.uiTitle(16))
                .foregroundStyle(Otobio.textSecondary)
            Text("Raconte ta journée ce soir")
                .font(Otobio.label())
                .foregroundStyle(Otobio.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    private func delete(_ entry: EntreeVocale) {
        viewContext.delete(entry)
        try? viewContext.save()
    }
}

// MARK: - Carte d'entrée (épurée : jour + titre + personnes)

struct EntryCard: View {
    @ObservedObject var entry: EntreeVocale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.dateEnregistrement ?? Date(), format: .dateTime.weekday(.wide).day())
                    .font(Otobio.micro())
                    .foregroundStyle(Otobio.textTertiary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Otobio.textTertiary)
            }

            if let titre = entry.titre, !titre.isEmpty {
                Text(titre)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Otobio.textPrimary)
            } else {
                // Le titre s'écrit encore — skeleton plutôt qu'un texte d'attente
                SkeletonBar(width: 150, height: 14)
                    .padding(.vertical, 2)
            }

            let personnes = Array((entry.personnes as? Set<Personne>) ?? []).sorted { ($0.nom ?? "") < ($1.nom ?? "") }
            if !personnes.isEmpty {
                HStack(spacing: 4) {
                    ForEach(personnes.prefix(3), id: \.self) { personne in
                        HStack(spacing: 3) {
                            Image(systemName: "person")
                                .font(.system(size: 9))
                            Text(personne.nom ?? "")
                                .font(Otobio.micro())
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Otobio.entityPerson.opacity(0.15))
                        .foregroundStyle(Otobio.entityPerson)
                        .clipShape(Capsule())
                    }
                    if personnes.count > 3 {
                        Text("+\(personnes.count - 3)")
                            .font(Otobio.micro())
                            .foregroundStyle(Otobio.textTertiary)
                    }
                }
            }
        }
        .otobioCard(padding: 14, radius: 14, background: Otobio.recitCardBackground)
        .contentShape(Rectangle())
    }
}

// MARK: - Page de détail d'une entrée (lecture + édition plein écran)

struct EntryDetailView: View {
    @ObservedObject var entry: EntreeVocale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var editedText: String = ""
    @State private var isEditing = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Otobio.recitCardBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.dateEnregistrement ?? Date(), format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .font(Otobio.micro())
                        .foregroundStyle(Otobio.textTertiary)
                        .padding(.top, 72)

                    Text(titleText)
                        .font(Otobio.serifTitle(26))
                        .foregroundStyle(Otobio.brand)
                        .padding(.top, 6)

                    Rectangle()
                        .fill(Otobio.separator)
                        .frame(width: 60, height: 0.5)
                        .padding(.vertical, 20)

                    if let resume = entry.resumeEntree, !resume.isEmpty {
                        Text(resume)
                            .font(Otobio.serifBody(17))
                            .foregroundStyle(Otobio.textPrimary)
                            .lineSpacing(8)
                            .padding(.bottom, 28)
                    }

                    Text("Transcription")
                        .font(Otobio.uiTitle(14))
                        .foregroundStyle(Otobio.textSecondary)
                        .padding(.bottom, 10)

                    if isEditing {
                        TextEditor(text: $editedText)
                            .font(Otobio.bodyText(15))
                            .foregroundStyle(Otobio.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 200)
                            .background(Otobio.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text(editedText)
                            .font(Otobio.bodyText(15))
                            .foregroundStyle(Otobio.textSecondary)
                            .lineSpacing(5)
                    }

                    Spacer(minLength: 110)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Otobio.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Otobio.cardBackground)
                    .clipShape(Circle())
            }
            .padding(.trailing, 20)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            floatingEditButton
        }
        .onAppear {
            editedText = entry.transcriptionCorrigee ?? entry.transcriptionBrute ?? ""
        }
    }

    /// Bouton flottant centré en bas — lecture pure, action évidente.
    private var floatingEditButton: some View {
        Button {
            if isEditing {
                entry.transcriptionCorrigee = editedText
                try? viewContext.save()
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                isEditing.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isEditing ? "checkmark" : "pencil")
                    .font(.system(size: 13, weight: .semibold))
                Text(isEditing ? "Enregistrer" : "Modifier")
                    .font(Otobio.label(15))
            }
            .foregroundStyle(Otobio.background)
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .background(Otobio.brand)
            .clipShape(Capsule())
            .shadow(color: Otobio.overlayScrim.opacity(0.18), radius: 12, x: 0, y: 4)
        }
        .padding(.bottom, 20)
    }

    private var titleText: String {
        if let titre = entry.titre, !titre.isEmpty { return titre }
        return "Entrée du jour"
    }
}
