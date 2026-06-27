import SwiftUI

struct TaggedTextView: View {
    let taggedText: TaggedText
    let onTagTap: (TaggedSegment) -> Void

    var body: some View {
        WrappingHStack(segments: taggedText.segments, onTagTap: onTagTap)
    }
}

private struct WrappingHStack: View {
    let segments: [TaggedSegment]
    let onTagTap: (TaggedSegment) -> Void

    var body: some View {
        Text(buildAttributedString())
            .font(.body)
            .environment(\.openURL, OpenURLAction { url in
                if let idx = Int(url.absoluteString.replacingOccurrences(of: "tag://", with: "")),
                   idx < segments.count {
                    onTagTap(segments[idx])
                }
                return .handled
            })
    }

    private func buildAttributedString() -> AttributedString {
        var result = AttributedString()

        for (index, segment) in segments.enumerated() {
            var part = AttributedString(segment.text)

            if let type = segment.entity {
                part.foregroundColor = color(for: type)
                part.font = .body.bold()
                part.underlineStyle = .single
                part.link = URL(string: "tag://\(index)")
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

#Preview {
    let entities = [
        DetectedEntity(text: "Dublin", type: .place, range: "à Dublin".range(of: "Dublin")!),
    ]
    let tagged = TaggedText(rawText: "Je suis allé à Dublin faire un trail.", entities: entities)
    TaggedTextView(taggedText: tagged) { segment in
        print("Tapped: \(segment.text)")
    }
    .padding()
}
