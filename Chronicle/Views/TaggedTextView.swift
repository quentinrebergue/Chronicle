import SwiftUI

struct TaggedTextView: View {
    let taggedText: TaggedText
    let onTagTap: (TaggedSegment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(buildAttributedString())
                .font(Otobio.bodyText())
                .frame(maxWidth: .infinity, alignment: .leading)

            let entitySegments = taggedText.segments.filter { $0.entity != nil }
            if !entitySegments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(entitySegments) { segment in
                            Button(action: { onTagTap(segment) }) {
                                HStack(spacing: 4) {
                                    Image(systemName: icon(for: segment.entity!))
                                        .font(.system(size: 10))
                                    Text(segment.text)
                                        .font(Otobio.micro(12))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(color(for: segment.entity!).opacity(0.12))
                                .foregroundStyle(color(for: segment.entity!))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(color(for: segment.entity!).opacity(0.3), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func buildAttributedString() -> AttributedString {
        var result = AttributedString()

        for segment in taggedText.segments {
            var part = AttributedString(segment.text)
            if let type = segment.entity {
                part.foregroundColor = color(for: type)
                part.font = Otobio.bodyText().bold()
            } else {
                part.foregroundColor = Otobio.marronNuit
            }
            result.append(part)
        }

        return result
    }

    private func color(for type: DetectedEntity.EntityType) -> Color {
        switch type {
        case .place: Otobio.entityPlace
        case .person: Otobio.entityPerson
        case .organization: Otobio.accent
        case .event: Otobio.entityEvent
        case .activity: Otobio.entityActivity
        }
    }

    private func icon(for type: DetectedEntity.EntityType) -> String {
        switch type {
        case .place: "mappin"
        case .person: "person"
        case .organization: "building.2"
        case .event: "star"
        case .activity: "figure.run"
        }
    }
}

struct TagEditorSheet: View {
    let segment: TaggedSegment
    @Binding var isPresented: Bool
    let onSave: (String, DetectedEntity.EntityType?) -> Void

    @State private var editedText: String = ""
    @State private var selectedType: DetectedEntity.EntityType?

    var body: some View {
        NavigationStack {
            Form {
                Section("Texte") {
                    TextField("Nom", text: $editedText)
                        .autocorrectionDisabled()
                }

                Section("Type d'entité") {
                    Picker("Type", selection: $selectedType) {
                        Text("Lieu").tag(DetectedEntity.EntityType?.some(.place))
                        Text("Personne").tag(DetectedEntity.EntityType?.some(.person))
                        Text("Événement").tag(DetectedEntity.EntityType?.some(.event))
                        Text("Activité").tag(DetectedEntity.EntityType?.some(.activity))
                        Text("Supprimer le tag").tag(DetectedEntity.EntityType?.none)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        onSave(editedText, selectedType)
                        isPresented = false
                    }
                    .bold()
                }
            }
        }
        .onAppear {
            editedText = segment.text
            selectedType = segment.entity
        }
    }
}
