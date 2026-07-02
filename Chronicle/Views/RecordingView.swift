import SwiftUI

struct RecordingView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var vm = RecordingViewModel()
    @ObservedObject var llmService: LLMService
    var onMenuTap: () -> Void
    @State private var editingSegment: TaggedSegment?
    @State private var showingTagEditor = false
    @State private var dragOffset: CGFloat = 0

    private let dragThreshold: CGFloat = 70

    var body: some View {
        ZStack {
            Otobio.background.ignoresSafeArea()

            if vm.state == .done {
                resultScreen
                    .transition(.opacity)
            } else {
                recordingScreen
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: vm.state == .done)
        .onAppear { vm.setup(context: viewContext, llmService: llmService) }
        .sheet(isPresented: $showingTagEditor) {
            if let segment = editingSegment {
                TagEditorSheet(segment: segment, isPresented: $showingTagEditor) { newText, newType in
                    vm.handleTagEdit(segment: segment, newText: newText, newType: newType)
                }
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Recording Screen

    private var recordingScreen: some View {
        VStack(spacing: 0) {
            OtobioTopBar(title: "Otobio", isBrandTitle: true, onMenuTap: onMenuTap)

            Spacer()

            statusText

            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(Otobio.micro())
                .foregroundStyle(Otobio.textTertiary)
                .padding(.top, 14)

            Spacer()

            if vm.state == .recording {
                gestureZones.padding(.bottom, 16)
            }

            recordButton.padding(.bottom, 8)

            if vm.state == .idle {
                Text("touche pour parler")
                    .font(Otobio.micro())
                    .foregroundStyle(Otobio.textTertiary)
            } else if vm.state == .recording {
                Text("glisse à gauche pour annuler")
                    .font(Otobio.micro())
                    .foregroundStyle(Otobio.textTertiary)
                    .opacity(dragOffset < -20 ? 0 : 1)
            } else if vm.state == .transcribing || vm.state == .processing {
                ProgressView()
                    .tint(Otobio.brand)
            }

            Spacer().frame(height: 40)
        }
    }

    // MARK: - Zones gestuelles (supprimer / valider)

    private var gestureZones: some View {
        HStack(spacing: 0) {
            zoneLabel(
                icon: "trash",
                label: "supprimer",
                isActive: dragOffset < -dragThreshold
            )
            Spacer()
            zoneLabel(
                icon: "checkmark",
                label: "valider",
                isActive: dragOffset > dragThreshold
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 36)
    }

    private func zoneLabel(icon: String, label: String, isActive: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(label)
                .font(Otobio.micro())
        }
        .foregroundStyle(isActive ? Otobio.brand : Otobio.textTertiary)
        .opacity(isActive ? 1 : 0.4)
        .scaleEffect(isActive ? 1.15 : 1)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }

    /// La question du jour — l'appel à l'action, adapté au moment de la journée.
    private var dailyQuestion: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Comment a commencé\nta journée ?"
        case 12..<18: return "Comment se passe\nta journée ?"
        default: return "Comment s'est passée\nta journée ?"
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch vm.state {
        case .idle:
            Text(dailyQuestion)
                .font(Otobio.serifTitle(28))
                .foregroundStyle(Otobio.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        case .recording:
            VStack(spacing: 8) {
                Text("● \(vm.formattedTime)")
                    .font(Otobio.label(14))
                    .foregroundStyle(Otobio.brand)
                Text("\(vm.remainingTime) restant")
                    .font(Otobio.micro())
                    .foregroundStyle(Otobio.textTertiary)
            }
        case .transcribing, .processing:
            VStack(spacing: 20) {
                // L'entrée prend forme : le contenu arrive, sa place est déjà là
                skeletonEntryCard
                pipelineStepsView
            }
        case .done:
            EmptyView()
        case .error(let msg):
            Text(msg)
                .font(Otobio.label(14))
                .foregroundStyle(Otobio.destructive)
        }
    }

    private var recordButton: some View {
        let isBusy = vm.state == .transcribing || vm.state == .processing

        return OrganicRingButton(
            isRecording: vm.state == .recording,
            isBusy: isBusy,
            audioLevels: vm.audioLevels
        )
        .offset(x: vm.state == .recording ? dragOffset : 0)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard vm.state == .recording else { return }
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    handleRelease(translation: value.translation.width)
                }
        )
        .disabled(isBusy)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragOffset == 0)
    }

    private func handleRelease(translation: CGFloat) {
        defer { dragOffset = 0 }

        switch vm.state {
        case .idle:
            if abs(translation) < dragThreshold {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                vm.toggleRecording()
            }
        case .recording:
            if translation < -dragThreshold {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                vm.cancelRecording()
            } else {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                vm.toggleRecording()
            }
        default:
            break
        }
    }

    private var skeletonEntryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBar(width: 150, height: 15)
            SkeletonBar(height: 11)
            SkeletonBar(width: 200, height: 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .otobioCard(padding: 16, background: Otobio.recitCardBackground)
        .padding(.horizontal, 40)
    }

    private var pipelineStepsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(vm.pipelineSteps) { step in
                HStack(spacing: 10) {
                    Group {
                        switch step.status {
                        case .active:
                            ProgressView()
                                .scaleEffect(0.7)
                        case .done:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Otobio.success)
                        case .failed:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Otobio.destructive)
                        case .pending:
                            Image(systemName: "circle")
                                .foregroundStyle(Otobio.textTertiary)
                        }
                    }
                    .frame(width: 20)

                    Image(systemName: step.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(step.status == .active ? Otobio.brand : Otobio.textTertiary)
                        .frame(width: 16)

                    if step.status == .active {
                        RotatingStatusText(
                            phrases: phrases(for: step.label),
                            font: Otobio.label(13),
                            color: Otobio.textPrimary
                        )
                    } else {
                        Text(step.label)
                            .font(Otobio.label(13))
                            .foregroundStyle(Otobio.textSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, 40)
    }

    /// Associe chaque étape du pipeline à son pool de phrases de progression.
    private func phrases(for stepLabel: String) -> [String] {
        switch stepLabel {
        case "Transcription": GenerationPhrase.transcribing
        case "Détection d'entités", "Extraction de relations": GenerationPhrase.extracting
        case "Vérification IA": GenerationPhrase.verifying
        case "Résumé narratif": GenerationPhrase.dailySummary
        default: [stepLabel]
        }
    }

    private var resultScreen: some View {
        VStack(spacing: 0) {
            OtobioTopBar(title: "Otobio", isBrandTitle: true, onMenuTap: onMenuTap)
            resultContent
        }
    }

    private var resultContent: some View {
        ResultView(
            taggedText: vm.taggedText,
            transcription: vm.transcription,
            relations: $vm.lastRelations,
            dailyTitle: vm.dailyTitle,
            dailySummary: vm.dailySummary,
            onTagTap: { segment in
                editingSegment = segment
                showingTagEditor = true
            },
            onNewEntry: { vm.reset() }
        )
    }
}
