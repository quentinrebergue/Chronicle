import SwiftUI

/// Le blob organique animé — bouton principal d'enregistrement.
/// Rempli, avec une icône waveform couleur parchemin en son centre.
/// Au repos : morphing lent + rotation, comme de l'encre vivante.
/// En enregistrement : la déformation réagit au niveau audio, la waveform s'anime avec la voix.
struct OrganicRingButton: View {
    let isRecording: Bool
    let isBusy: Bool
    let audioLevels: [Float]

    private let baseSize: CGFloat = 96

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                blobShape(time: t)
                    .fill(isRecording ? Otobio.entityPerson : Otobio.brand)
                    .frame(width: baseSize, height: baseSize)
                    .animation(.easeInOut(duration: 0.3), value: isRecording)

                if isBusy {
                    ProgressView()
                        .tint(Otobio.background)
                } else {
                    innerWaveform
                        .frame(width: baseSize - 40, height: 28)
                }
            }
        }
        .frame(width: baseSize + 20, height: baseSize + 20)
        .contentShape(Circle())
    }

    // MARK: - Blob morphing

    private func blobShape(time: TimeInterval) -> Path {
        let level = CGFloat(audioLevels.suffix(6).reduce(0, +) / 6)
        let reactivity: CGFloat = isRecording ? 1 + level * 1.8 : 1

        let rotation = time * (isRecording ? 0.35 : 0.14) // ~12s/tour au repos
        let breathSpeed = isRecording ? 3.2 : 0.55

        let points = 7
        let radius = baseSize / 2
        let noiseAmp = radius * 0.09 * reactivity

        var vertices: [CGPoint] = []
        for i in 0..<points {
            let angle = (Double(i) / Double(points)) * 2 * .pi + rotation
            let wobble = sin(angle * 3 + time * breathSpeed) * 0.6
                + cos(angle * 2 - time * breathSpeed * 0.7) * 0.4
            let r = radius + noiseAmp * CGFloat(wobble)
            let x = baseSize / 2 + cos(angle) * r
            let y = baseSize / 2 + sin(angle) * r
            vertices.append(CGPoint(x: x, y: y))
        }

        return smoothClosedPath(through: vertices)
    }

    /// Courbe de Catmull-Rom convertie en Bézier — un contour fermé et lisse à travers les points.
    private func smoothClosedPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }

        path.move(to: points[0])
        let n = points.count
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]

            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)

            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Waveform intérieure

    /// Au repos : petites barres statiques symétriques. En enregistrement : réagit au niveau audio réel.
    private var innerWaveform: some View {
        HStack(spacing: 3) {
            ForEach(0..<9, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Otobio.background)
                    .frame(width: 3, height: barHeight(at: i))
            }
        }
        .animation(.easeOut(duration: 0.06), value: audioLevels)
    }

    /// Silhouette irrégulière au repos — évite l'effet "losange" trop régulier.
    private static let idlePattern: [CGFloat] = [9, 22, 13, 27, 11, 24, 16, 8, 19]

    private func barHeight(at index: Int) -> CGFloat {
        guard isRecording else {
            return Self.idlePattern[index]
        }
        let recent = Array(audioLevels.suffix(9))
        guard index < recent.count else { return 6 }
        return max(5, CGFloat(recent[index]) * 28)
    }
}

#Preview {
    VStack(spacing: 40) {
        OrganicRingButton(isRecording: false, isBusy: false, audioLevels: Array(repeating: 0, count: 40))
        OrganicRingButton(isRecording: true, isBusy: false, audioLevels: (0..<40).map { _ in Float.random(in: 0.1...0.9) })
    }
    .padding(60)
    .background(Otobio.background)
}
