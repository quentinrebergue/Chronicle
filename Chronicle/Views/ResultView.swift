import SwiftUI

struct ResultView: View {
    let taggedText: TaggedText?
    let transcription: String
    @Binding var relations: [EntityRelation]
    let dailyTitle: String
    let dailySummary: String
    let onTagTap: (TaggedSegment) -> Void
    let onNewEntry: () -> Void

    @State private var appeared = false
    @State private var showDetail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                // Le héros : la voix devenue prose
                if !dailySummary.isEmpty {
                    summarySection
                }

                detailToggle

                if showDetail {
                    if !relations.isEmpty { eventsSection }
                    transcriptionSection
                }

                newEntryButton
            }
            .padding(20)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
        }
        .background(Otobio.background)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Entrée enregistrée")
                .font(Otobio.uiTitle(20))
                .foregroundStyle(Otobio.textPrimary)
            Spacer()
            Text(Date(), style: .time)
                .font(Otobio.micro())
                .foregroundStyle(Otobio.textTertiary)
        }
    }

    // MARK: - Résumé (le héros)

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !dailyTitle.isEmpty {
                Text(dailyTitle)
                    .font(Otobio.serifTitle(22))
                    .foregroundStyle(Otobio.brand)
            }

            Text(dailySummary)
                .font(.custom("TimesNewRomanPSMT", size: 16))
                .foregroundStyle(Otobio.textPrimary)
                .lineSpacing(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .otobioCard(padding: 20, background: Otobio.recitCardBackground)
    }

    // MARK: - Détail repliable

    private var detailToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                showDetail.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(showDetail ? "Masquer le détail" : "Voir le détail")
                    .font(Otobio.label(13))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(showDetail ? 180 : 0))
            }
            .foregroundStyle(Otobio.textSecondary)
        }
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Événements")
                .font(Otobio.uiTitle(15))
                .foregroundStyle(Otobio.textSecondary)

            ForEach(Array(relations.enumerated()), id: \.offset) { index, _ in
                EventCard(relation: $relations[index], onDelete: {
                    relations.remove(at: index)
                })
            }
        }
        .animation(.easeOut(duration: 0.3), value: relations.count)
    }

    // MARK: - Transcription

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcription")
                .font(Otobio.uiTitle(15))
                .foregroundStyle(Otobio.textSecondary)

            if let tagged = taggedText {
                TaggedTextView(taggedText: tagged, onTagTap: onTagTap)
            } else {
                Text(transcription)
                    .font(Otobio.bodyText())
                    .foregroundStyle(Otobio.textPrimary)
            }
        }
        .otobioCard()
    }

    // MARK: - New entry

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

// MARK: - Event Card (collapsible)

struct EventCard: View {
    @Binding var relation: EntityRelation
    let onDelete: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(relation.event)
                        .font(Otobio.label(14))
                        .bold()
                        .foregroundStyle(Otobio.textPrimary)
                        .lineLimit(1)

                    if let loc = relation.locations.first {
                        MiniChip(text: loc, color: Otobio.entityPlace)
                    }

                    if let person = relation.persons.first {
                        MiniChip(text: person, color: Otobio.entityPerson)
                    }

                    if relation.persons.count > 1 {
                        Text("+\(relation.persons.count - 1)")
                            .font(Otobio.micro())
                            .foregroundStyle(Otobio.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Otobio.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .padding(12)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Rectangle()
                        .fill(Otobio.separator)
                        .frame(height: 0.5)
                        .padding(.horizontal, 12)

                    if !relation.description.isEmpty {
                        Text(relation.description)
                            .font(Otobio.bodyText(13))
                            .foregroundStyle(Otobio.textSecondary)
                            .lineSpacing(2)
                            .padding(.horizontal, 12)
                    }

                    // Lieux
                    if !relation.locations.isEmpty {
                        HStack(spacing: 6) {
                            Text("Lieux")
                                .font(Otobio.micro(11))
                                .foregroundStyle(Otobio.textTertiary)
                                .frame(width: 55, alignment: .leading)

                            FlowLayout(spacing: 4) {
                                ForEach(relation.locations, id: \.self) { loc in
                                    EntityChip(text: loc, type: .place)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }

                    // Personnes
                    if !relation.persons.isEmpty {
                        HStack(spacing: 6) {
                            Text("Personnes")
                                .font(Otobio.micro(11))
                                .foregroundStyle(Otobio.textTertiary)
                                .frame(width: 55, alignment: .leading)

                            FlowLayout(spacing: 4) {
                                ForEach(relation.persons, id: \.self) { person in
                                    EntityChip(text: person, type: .person)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }

                    // Delete
                    HStack {
                        Spacer()
                        Button(action: onDelete) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                Text("Supprimer")
                                    .font(Otobio.micro())
                            }
                            .foregroundStyle(Otobio.destructive.opacity(0.8))
                            .padding(6)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .otobioCard(padding: 0, radius: 12)
    }
}

// MARK: - Mini Chip (compact, for collapsed header)

struct MiniChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(Otobio.micro(10))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}
