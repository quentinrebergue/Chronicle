import Foundation

struct TaggedSegment: Identifiable {
    let id = UUID()
    let text: String
    let entity: DetectedEntity.EntityType?
    let range: Range<String.Index>
}

struct TaggedText {
    let segments: [TaggedSegment]
    let rawText: String

    init(rawText: String, entities: [DetectedEntity]) {
        self.rawText = rawText

        var segments: [TaggedSegment] = []
        var currentIndex = rawText.startIndex

        let sorted = entities.sorted { $0.range.lowerBound < $1.range.lowerBound }

        for entity in sorted {
            guard entity.range.lowerBound >= currentIndex else { continue }

            if currentIndex < entity.range.lowerBound {
                segments.append(TaggedSegment(
                    text: String(rawText[currentIndex..<entity.range.lowerBound]),
                    entity: nil,
                    range: currentIndex..<entity.range.lowerBound
                ))
            }

            segments.append(TaggedSegment(
                text: entity.text,
                entity: entity.type,
                range: entity.range
            ))

            currentIndex = entity.range.upperBound
        }

        if currentIndex < rawText.endIndex {
            segments.append(TaggedSegment(
                text: String(rawText[currentIndex..<rawText.endIndex]),
                entity: nil,
                range: currentIndex..<rawText.endIndex
            ))
        }

        self.segments = segments
    }
}
