import SwiftUI

struct RecordingView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var vm = RecordingViewModel()
    @ObservedObject var llmService: LLMService
    @State private var editingSegment: TaggedSegment?
    @State private var showingTagEditor = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                timerDisplay

                waveformView

                recordButton

                statusText

                if vm.state == .done {
                    transcriptionCard
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationTitle("Chronicle")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    llmBadge
                }
            }
            .onAppear { vm.setup(context: viewContext, llmService: llmService) }
        }
    }

    // MARK: - LLM Badge

    private var llmBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(llmService.isLoaded ? .green : .orange)
                .frame(width: 8, height: 8)
            Text(llmService.isLoaded ? "LLM" : "Chargement…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Timer

    private var timerDisplay: some View {
        VStack(spacing: 4) {
            Text(vm.formattedTime)
                .font(.system(size: 56, weight: .thin, design: .monospaced))
                .foregroundStyle(vm.state == .recording ? .primary : .secondary)

            if vm.state == .recording {
                Text("\(vm.remainingTime) restant")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Waveform

    private var waveformView: some View {
        HStack(spacing: 2) {
            ForEach(Array(vm.audioLevels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(vm.state == .recording ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 3, height: max(3, CGFloat(level) * 60))
            }
        }
        .frame(height: 64)
        .animation(.easeOut(duration: 0.05), value: vm.audioLevels)
    }

    // MARK: - Record button

    private var recordButton: some View {
        Button(action: vm.toggleRecording) {
            ZStack {
                Circle()
                    .fill(buttonColor.opacity(0.15))
                    .frame(width: 88, height: 88)

                Circle()
                    .fill(buttonColor)
                    .frame(width: 68, height: 68)

                if vm.state == .recording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 22, height: 22)
                } else if vm.state == .transcribing || vm.state == .processing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .disabled(vm.state == .transcribing || vm.state == .processing)
    }

    private var buttonColor: Color {
        switch vm.state {
        case .recording: return .red
        case .transcribing, .processing: return .orange
        default: return .accentColor
        }
    }

    // MARK: - Status

    private var statusText: some View {
        Group {
            switch vm.state {
            case .idle:
                Text("Appuie pour raconter ta journée")
            case .recording:
                Text("Enregistrement en cours…")
            case .transcribing:
                Text(vm.llmStatus.isEmpty ? "Transcription…" : vm.llmStatus)
            case .processing:
                Text(vm.llmStatus.isEmpty ? "Analyse…" : vm.llmStatus)
            case .done:
                Text("Entrée sauvegardée ✓")
            case .error(let msg):
                Text(msg)
                    .foregroundStyle(.red)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    // MARK: - Transcription

    private var transcriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if vm.taggedText != nil {
                    Text("Tap sur un tag pour le modifier")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            ScrollView {
                if let tagged = vm.taggedText {
                    TaggedTextView(taggedText: tagged) { segment in
                        editingSegment = segment
                        showingTagEditor = true
                    }
                } else {
                    Text(vm.transcription)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: 200)


            Button("Nouvelle entrée") {
                vm.reset()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingTagEditor) {
            if let segment = editingSegment {
                TagEditorSheet(segment: segment, isPresented: $showingTagEditor) { newText, newType in
                    vm.handleTagEdit(segment: segment, newText: newText, newType: newType)
                }
                .presentationDetents([.medium])
            }
        }
    }
}

#Preview {
    RecordingView(llmService: LLMService())
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
