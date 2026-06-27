import SwiftUI

struct TaggedTextView: View {
    let taggedText: TaggedText
    let onTagTap: (TaggedSegment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Texte avec couleurs inline
            Text(buildAttributedString())
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Chips d'entités cliquables
            let entitySegments = taggedText.segments.filter { $0.entity != nil }
            if !entitySegments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(entitySegments) { segment in
                            Button(action: { onTagTap(segment) }) {
                                HStack(spacing: 4) {
                                    Image(systemName: icon(for: segment.entity!))
                                        .font(.caption2)
                                    Text(segment.text)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(color(for: segment.entity!).opacity(0.15))
                                .foregroundStyle(color(for: segment.entity!))
                                .clipShape(Capsule())
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
                part.font = .body.bold()
            }
            result.append(part)
        }

        return result
    }

    private func color(for type: DetectedEntity.EntityType) -> Color {
        switch type {
        case .place: .blue
        case .person: .green
        case .organization: .orange
        case .event: .yellow
        case .activity: .purple
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
                        Text("Organisation").tag(DetectedEntity.EntityType?.some(.organization))
                        Text("Événement").tag(DetectedEntity.EntityType?.some(.event))
                        Text("Activité").tag(DetectedEntity.EntityType?.some(.activity))
                        Text("Aucun (supprimer le tag)").tag(DetectedEntity.EntityType?.none)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Modifier l'entité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
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
