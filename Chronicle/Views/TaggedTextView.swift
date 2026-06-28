import SwiftUI

struct TaggedTextView: View {
    let taggedText: TaggedText
    let onTagTap: (TaggedSegment) -> Void

    var body: some View {
        FlowText(segments: taggedText.segments, onTagTap: onTagTap)
    }
}

// Inline flow text with entity chips
private struct FlowText: View {
    let segments: [TaggedSegment]
    let onTagTap: (TaggedSegment) -> Void

    var body: some View {
        var result = Text("")

        for segment in segments {
            if segment.entity != nil {
                // Can't make Text tappable inline, so we render all as Text
                // with colored styling — chips below for interaction
                result = result + Text(segment.text)
                    .foregroundColor(Otobio.entityColor(for: segment.entity!))
                    .bold()
            } else {
                result = result + Text(segment.text)
                    .foregroundColor(Otobio.textPrimary)
            }
        }

        return VStack(alignment: .leading, spacing: 10) {
            result.font(Otobio.bodyText())

            // Entity chips (tappable)
            let entitySegments = segments.filter { $0.entity != nil }
            if !entitySegments.isEmpty {
                entityChips(entitySegments)
            }
        }
    }

    private func entityChips(_ segments: [TaggedSegment]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(segments) { segment in
                EntityChip(text: segment.text, type: segment.entity!) {
                    onTagTap(segment)
                }
            }
        }
    }
}

// Reusable entity chip (used in tags AND event cards)
struct EntityChip: View {
    let text: String
    let type: DetectedEntity.EntityType
    var action: (() -> Void)? = nil

    var body: some View {
        let color = Otobio.entityColor(for: type)
        let icon = Otobio.entityIcon(for: type)

        Button(action: { action?() }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(text)
                    .font(Otobio.micro(12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

// Flow layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
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
            VStack(spacing: 0) {
                Form {
                    Section {
                        TextField("Nom", text: $editedText)
                            .autocorrectionDisabled()
                    }

                    Section {
                        Picker("Type", selection: $selectedType) {
                            Text("Lieu").tag(DetectedEntity.EntityType?.some(.place))
                            Text("Personne").tag(DetectedEntity.EntityType?.some(.person))
                            Text("Événement").tag(DetectedEntity.EntityType?.some(.event))
                            Text("Activité").tag(DetectedEntity.EntityType?.some(.activity))
                            Text("Supprimer").tag(DetectedEntity.EntityType?.none)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Otobio.background)
            }
            .background(Otobio.background)
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
                    }.bold()
                }
            }
        }
        .onAppear {
            editedText = segment.text
            selectedType = segment.entity
        }
    }
}
