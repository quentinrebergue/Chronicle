import SwiftUI

struct RecordingView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var vm = RecordingViewModel()
    @ObservedObject var llmService: LLMService
    @State private var editingSegment: TaggedSegment?
    @State private var showingTagEditor = false

    var body: some View {
        ZStack {
            Otobio.background.ignoresSafeArea()

            if vm.state == .done {
                resultScreen
            } else {
                recordingScreen
            }
        }
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
            Spacer()

            Text("Otobio")
                .font(Otobio.brandTitle(36))
                .foregroundStyle(Otobio.brand)

            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide).year())
                .font(Otobio.micro())
                .foregroundStyle(Otobio.textTertiary)
                .padding(.top, 4)

            Rectangle()
                .fill(Otobio.separator)
                .frame(width: 60, height: 0.5)
                .padding(.vertical, 16)

            statusText

            Spacer()

            if vm.state == .recording {
                waveformView.padding(.bottom, 20)
            }

            recordButton.padding(.bottom, 8)

            if vm.state == .idle {
                Text("maintiens pour parler")
                    .font(Otobio.micro())
                    .foregroundStyle(Otobio.textTertiary)
            } else if vm.state == .transcribing || vm.state == .processing {
                ProgressView()
                    .tint(Otobio.brand)
            }

            Spacer().frame(height: 40)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch vm.state {
        case .idle:
            VStack(spacing: 6) {
                Text("Comment s'est passée")
                    .font(Otobio.brandTitle(20))
                Text("ta journée ?")
                    .font(Otobio.brandTitle(20))
            }
            .foregroundStyle(Otobio.textPrimary)
        case .recording:
            VStack(spacing: 8) {
                Text("● \(vm.formattedTime)")
                    .font(Otobio.label(14))
                    .foregroundStyle(Otobio.brand)
                Text("\(vm.remainingTime) restant")
                    .font(Otobio.micro())
                    .foregroundStyle(Otobio.textTertiary)
            }
        case .transcribing:
            Text("Transcription…")
                .font(Otobio.label(14))
                .foregroundStyle(Otobio.textSecondary)
        case .processing:
            Text(vm.llmStatus.isEmpty ? "Analyse…" : vm.llmStatus)
                .font(Otobio.label(14))
                .foregroundStyle(Otobio.textSecondary)
        case .done:
            EmptyView()
        case .error(let msg):
            Text(msg)
                .font(Otobio.label(14))
                .foregroundStyle(.red)
        }
    }

    private var waveformView: some View {
        HStack(spacing: 2) {
            ForEach(Array(vm.audioLevels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Otobio.brand)
                    .frame(width: 3, height: max(3, CGFloat(level) * 50))
            }
        }
        .frame(height: 54)
        .animation(.easeOut(duration: 0.05), value: vm.audioLevels)
    }

    private var recordButton: some View {
        Button(action: vm.toggleRecording) {
            ZStack {
                Circle()
                    .stroke(
                        vm.state == .recording ? Otobio.brand.opacity(0.8) : Otobio.brand,
                        lineWidth: vm.state == .recording ? 6 : 4
                    )
                    .frame(width: 80, height: 80)

                if vm.state == .recording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Otobio.brand)
                        .frame(width: 24, height: 24)
                } else if vm.state == .transcribing || vm.state == .processing {
                    ProgressView()
                        .tint(Otobio.brand)
                } else {
                    Circle()
                        .fill(Otobio.brand)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .disabled(vm.state == .transcribing || vm.state == .processing)
    }

    private var resultScreen: some View {
        ResultView(
            taggedText: vm.taggedText,
            transcription: vm.transcription,
            relations: $vm.lastRelations,
            onTagTap: { segment in
                editingSegment = segment
                showingTagEditor = true
            },
            onNewEntry: { vm.reset() }
        )
    }
}
