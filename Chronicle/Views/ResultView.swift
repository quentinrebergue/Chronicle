import SwiftUI

struct ResultView: View {
    let taggedText: TaggedText?
    let transcription: String
    @Binding var relations: [EntityRelation]
    let onTagTap: (TaggedSegment) -> Void
    let onNewEntry: () -> Void

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
        .background(Otobio.background)
    }

    private var header: some View {
        HStack {
            Text("Entrée enregistrée")
                .font(Otobio.brandTitle(24))
                .foregroundStyle(Otobio.brand)
            Spacer()
            Text(Date(), style: .time)
                .font(Otobio.micro())
                .foregroundStyle(Otobio.textTertiary)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Otobio.separator)
            .frame(height: 0.5)
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ce que j'ai compris")
                .font(Otobio.sectionTitle(18))
                .foregroundStyle(Otobio.brand)

            ForEach(Array(relations.enumerated()), id: \.offset) { index, _ in
                EventCard(relation: $relations[index], onDelete: {
                    relations.remove(at: index)
                }, onEntityTap: onTagTap)
            }
        }
    }

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcription")
                .font(Otobio.sectionTitle(18))
                .foregroundStyle(Otobio.brand)

            if let tagged = taggedText {
                TaggedTextView(taggedText: tagged, onTagTap: onTagTap)
            } else {
                Text(transcription)
                    .font(Otobio.bodyText())
                    .foregroundStyle(Otobio.textPrimary)
            }
        }
        .padding(16)
        .background(Otobio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var newEntryButton: some View {
        Button(action: onNewEntry) {
            Text("Nouvelle entrée")
                .font(Otobio.label(15))
                .foregroundStyle(Otobio.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Otobio.brand)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.top, 8)
    }
}

// MARK: - Event Card (inline editable)

struct EventCard: View {
    @Binding var relation: EntityRelation
    let onDelete: () -> Void
    let onEntityTap: (TaggedSegment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Delete button
            HStack {
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Otobio.textTertiary)
                        .padding(6)
                }
            }
            .padding(.bottom, -8)

            // Description (editable)
            if !relation.description.isEmpty {
                Text(relation.description.count > 150 ? String(relation.description.prefix(150)) + "…" : relation.description)
                    .font(Otobio.bodyText(14))
                    .foregroundStyle(Otobio.textPrimary)
            } else {
                TextField("Description", text: $relation.event, axis: .vertical)
                    .font(Otobio.bodyText(14))
                    .foregroundStyle(Otobio.textPrimary)
            }

            // Lieux
            HStack(spacing: 6) {
                Text("Lieux")
                    .font(Otobio.micro(11))
                    .foregroundStyle(Otobio.textTertiary)
                    .frame(width: 60, alignment: .leading)

                if relation.locations.isEmpty {
                    Text("—")
                        .font(Otobio.label(13))
                        .foregroundStyle(Otobio.textTertiary)
                } else {
                    FlowLayout(spacing: 4) {
                        ForEach(relation.locations, id: \.self) { loc in
                            EntityChip(text: loc, type: .place)
                        }
                    }
                }
            }

            // Personnes
            HStack(spacing: 6) {
                Text("Personnes")
                    .font(Otobio.micro(11))
                    .foregroundStyle(Otobio.textTertiary)
                    .frame(width: 60, alignment: .leading)

                if relation.persons.isEmpty {
                    Text("—")
                        .font(Otobio.label(13))
                        .foregroundStyle(Otobio.textTertiary)
                } else {
                    FlowLayout(spacing: 4) {
                        ForEach(relation.persons, id: \.self) { person in
                            EntityChip(text: person, type: .person)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Otobio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}
