import SwiftUI

struct ResultView: View {
    let taggedText: TaggedText?
    let transcription: String
    @Binding var relations: [EntityRelation]
    let onTagTap: (TaggedSegment) -> Void
    let onNewEntry: () -> Void

    @State private var editingRelationIndex: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                separator
                if !relations.isEmpty { eventsSection }
                transcriptionSection
                newEntryButton
            }
            .padding(20)
        }
        .background(Otobio.parchemin)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Entrée enregistrée")
                .font(Otobio.brandTitle(24))
                .foregroundStyle(Otobio.marronFonce)
            Spacer()
            Text(Date(), style: .time)
                .font(Otobio.micro())
                .foregroundStyle(Otobio.accent)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Otobio.beigeDoré)
            .frame(height: 0.5)
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ce que j'ai compris")
                .font(Otobio.sectionTitle(18))
                .foregroundStyle(Otobio.marronFonce)

            ForEach(Array(relations.enumerated()), id: \.offset) { index, relation in
                EventCard(relation: relation, onEdit: {
                    editingRelationIndex = index
                }, onDelete: {
                    relations.remove(at: index)
                })
            }
        }
        .sheet(item: $editingRelationIndex) { index in
            EventEditorSheet(relation: $relations[index])
                .presentationDetents([.medium])
        }
    }

    // MARK: - Transcription

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcription")
                .font(Otobio.sectionTitle(18))
                .foregroundStyle(Otobio.marronFonce)

            if let tagged = taggedText {
                TaggedTextView(taggedText: tagged, onTagTap: onTagTap)
            } else {
                Text(transcription)
                    .font(Otobio.bodyText())
                    .foregroundStyle(Otobio.marronNuit)
            }
        }
        .padding(16)
        .background(Otobio.cremeAncien)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - New Entry

    private var newEntryButton: some View {
        Button(action: onNewEntry) {
            Text("Nouvelle entrée")
                .font(Otobio.label(15))
                .foregroundStyle(Otobio.parchemin)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Otobio.marronFonce)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.top, 8)
    }
}

// MARK: - Event Card

struct EventCard: View {
    let relation: EntityRelation
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title
            Text(relation.event.count > 80 ? String(relation.event.prefix(80)) + "…" : relation.event)
                .font(Otobio.bodyText(15))
                .fontWeight(.medium)
                .foregroundStyle(Otobio.marronFonce)

            // Structured details
            VStack(alignment: .leading, spacing: 6) {
                if !relation.locations.isEmpty {
                    HStack(spacing: 6) {
                        Text("Lieux")
                            .font(Otobio.micro(11))
                            .foregroundStyle(Otobio.accent)
                            .frame(width: 65, alignment: .leading)
                        Text(relation.locations.joined(separator: ", "))
                            .font(Otobio.label(13))
                            .foregroundStyle(Otobio.entityPlace)
                    }
                }

                if !relation.persons.isEmpty {
                    HStack(spacing: 6) {
                        Text("Personnes")
                            .font(Otobio.micro(11))
                            .foregroundStyle(Otobio.accent)
                            .frame(width: 65, alignment: .leading)
                        Text(relation.persons.joined(separator: ", "))
                            .font(Otobio.label(13))
                            .foregroundStyle(Otobio.entityPerson)
                    }
                }
            }

            // Actions
            HStack {
                Spacer()
                Button(action: onEdit) {
                    Text("Modifier")
                        .font(Otobio.micro(11))
                        .foregroundStyle(Otobio.marronChaud)
                }
                Text("·")
                    .foregroundStyle(Otobio.beigeDoré)
                Button(action: onDelete) {
                    Text("Supprimer")
                        .font(Otobio.micro(11))
                        .foregroundStyle(Otobio.accent)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Otobio.cremeAncien)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Event Editor

struct EventEditorSheet: View {
    @Binding var relation: EntityRelation
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var locations: String = ""
    @State private var persons: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(Otobio.micro(11))
                                .foregroundStyle(Otobio.accent)
                            TextField("Événement", text: $title, axis: .vertical)
                                .font(Otobio.bodyText())
                                .lineLimit(3...)
                        }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Lieux")
                                .font(Otobio.micro(11))
                                .foregroundStyle(Otobio.accent)
                            TextField("ex: Dublin, Howth", text: $locations)
                                .font(Otobio.bodyText())
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Personnes")
                                .font(Otobio.micro(11))
                                .foregroundStyle(Otobio.accent)
                            TextField("ex: Louise, Pierre", text: $persons)
                                .font(Otobio.bodyText())
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Otobio.parchemin)
            }
            .background(Otobio.parchemin)
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .foregroundStyle(Otobio.marronChaud)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        relation = EntityRelation(
                            event: title,
                            eventType: relation.eventType,
                            persons: persons.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                            locations: locations.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        )
                        dismiss()
                    }
                    .bold()
                    .foregroundStyle(Otobio.marronFonce)
                }
            }
        }
        .onAppear {
            title = relation.event
            locations = relation.locations.joined(separator: ", ")
            persons = relation.persons.joined(separator: ", ")
        }
    }
}

// Make Int identifiable for sheet
extension Int: @retroactive Identifiable {
    public var id: Int { self }
}
