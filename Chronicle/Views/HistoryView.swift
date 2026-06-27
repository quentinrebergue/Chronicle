import SwiftUI
import CoreData

struct HistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \EntreeVocale.dateEnregistrement, ascending: false)],
        animation: .default
    )
    private var entries: FetchedResults<EntreeVocale>

    @State private var editingEntry: EntreeVocale?
    @State private var showingEditor = false

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "Aucune entrée",
                        systemImage: "mic.slash",
                        description: Text("Enregistre ta première entrée vocale")
                    )
                } else {
                    ForEach(entries) { entry in
                        EntryRow(entry: entry)
                            .onTapGesture {
                                editingEntry = entry
                                showingEditor = true
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteEntry(entry)
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .navigationTitle("Historique")
            .sheet(isPresented: $showingEditor) {
                if let entry = editingEntry {
                    EntryEditorSheet(entry: entry, isPresented: $showingEditor)
                        .environment(\.managedObjectContext, viewContext)
                }
            }
        }
    }

    private func deleteEntry(_ entry: EntreeVocale) {
        viewContext.delete(entry)
        try? viewContext.save()
    }
}

struct EntryRow: View {
    @ObservedObject var entry: EntreeVocale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.dateEnregistrement ?? Date(), style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.dateEnregistrement ?? Date(), style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let emotion = entry.emotionDominante {
                    Text(emotion)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.purple.opacity(0.15))
                        .clipShape(Capsule())
                }
                Text(formatDuration(entry.dureeSecondes))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.transcriptionCorrigee ?? entry.transcriptionBrute ?? "")
                .font(.subheadline)
                .lineLimit(3)

            // Entity chips
            let personnes = (entry.personnes as? Set<Personne>) ?? []
            if !personnes.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(personnes), id: \.self) { personne in
                        Text(personne.nom ?? "")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}

struct EntryEditorSheet: View {
    @ObservedObject var entry: EntreeVocale
    @Binding var isPresented: Bool
    @Environment(\.managedObjectContext) private var viewContext

    @State private var editedText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    Text(entry.dateEnregistrement ?? Date(), format: .dateTime)
                }

                Section("Transcription") {
                    TextEditor(text: $editedText)
                        .frame(minHeight: 150)
                }

                if let brut = entry.transcriptionBrute, brut != editedText {
                    Section("Transcription brute") {
                        Text(brut)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Modifier l'entrée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        entry.transcriptionCorrigee = editedText
                        try? viewContext.save()
                        isPresented = false
                    }
                    .bold()
                }
            }
        }
        .onAppear {
            editedText = entry.transcriptionCorrigee ?? entry.transcriptionBrute ?? ""
        }
    }
}
