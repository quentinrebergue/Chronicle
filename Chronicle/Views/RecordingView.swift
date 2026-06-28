import SwiftUI

struct RecordingView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var vm = RecordingViewModel()
    @ObservedObject var llmService: LLMService
    @State private var editingSegment: TaggedSegment?
    @State private var showingTagEditor = false

    var body: some View {
        ZStack {
            Otobio.parchemin.ignoresSafeArea()

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

            // Brand
            Text("Otobio")
                .font(Otobio.brandTitle(36))
                .foregroundStyle(Otobio.marronFonce)

            // Date
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide).year())
                .font(Otobio.micro())
                .foregroundStyle(Otobio.accent)
                .padding(.top, 4)

            // Separator
            Rectangle()
                .fill(Otobio.beigeDoré)
                .frame(width: 60, height: 1)
                .padding(.vertical, 16)

            // Question or status
            Group {
                switch vm.state {
                case .idle:
                    VStack(spacing: 6) {
                        Text("Comment s'est passée")
                            .font(Otobio.brandTitle(20))
                        Text("ta journée ?")
                            .font(Otobio.brandTitle(20))
                    }
                case .recording:
                    VStack(spacing: 8) {
                        Text("● \(vm.formattedTime)")
                            .font(Otobio.label(14))
                            .foregroundStyle(Otobio.marronChaud)
                        Text("\(vm.remainingTime) restant")
                            .font(Otobio.micro())
                            .foregroundStyle(Otobio.accent)
                    }
                case .transcribing:
                    Text("Transcription…")
                        .font(Otobio.label(14))
                case .processing:
                    Text(vm.llmStatus.isEmpty ? "Analyse…" : vm.llmStatus)
                        .font(Otobio.label(14))
                case .done:
                    EmptyView()
                case .error(let msg):
                    Text(msg)
                        .font(Otobio.label(14))
                        .foregroundStyle(.red)
                }
            }
            .foregroundStyle(Otobio.marronFonce)

            Spacer()

            // Waveform
            if vm.state == .recording {
                waveformView
                    .padding(.bottom, 20)
            }

            // Record button
            recordButton
                .padding(.bottom, 8)

            // Hint
            if vm.state == .idle {
                Text("maintiens pour parler")
                    .font(Otobio.micro())
                    .foregroundStyle(Otobio.beigeDoré)
            } else if vm.state == .transcribing || vm.state == .processing {
                ProgressView()
                    .tint(Otobio.marronChaud)
            }

            Spacer()
                .frame(height: 40)
        }
    }

    // MARK: - Waveform

    private var waveformView: some View {
        HStack(spacing: 2) {
            ForEach(Array(vm.audioLevels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Otobio.marronChaud)
                    .frame(width: 3, height: max(3, CGFloat(level) * 50))
            }
        }
        .frame(height: 54)
        .animation(.easeOut(duration: 0.05), value: vm.audioLevels)
    }

    // MARK: - Record Button (organic ring)

    private var recordButton: some View {
        Button(action: vm.toggleRecording) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(
                        vm.state == .recording ? Otobio.marronChaud : Otobio.marronFonce,
                        lineWidth: vm.state == .recording ? 6 : 4
                    )
                    .frame(width: 80, height: 80)

                // Inner
                if vm.state == .recording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Otobio.marronChaud)
                        .frame(width: 24, height: 24)
                } else if vm.state == .transcribing || vm.state == .processing {
                    ProgressView()
                        .tint(Otobio.marronFonce)
                } else {
                    Circle()
                        .fill(Otobio.marronFonce)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .disabled(vm.state == .transcribing || vm.state == .processing)
    }

    // MARK: - Result Screen

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
