import SwiftUI

struct TaggedTextView: View {
    let taggedText: TaggedText
    let onTagTap: (TaggedSegment) -> Void

    var body: some View {
        FlowLayout(spacing: 0) {
            ForEach(taggedText.segments) { segment in
                if let type = segment.entity {
                    Button(action: { onTagTap(segment) }) {
                        Text(segment.text)
                            .font(.body.bold())
                            .foregroundStyle(color(for: type))
                            .underline()
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(segment.text)
                        .font(.body)
                }
            }
        }
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

// Simple flow layout that wraps content
struct FlowLayout: Layout {
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
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
