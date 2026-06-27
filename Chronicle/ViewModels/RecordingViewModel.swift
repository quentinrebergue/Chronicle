import Foundation
import SwiftUI
import CoreData

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var transcription: String = ""
    @Published var elapsedTime: TimeInterval = 0
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 40)

    enum RecordingState {
        case idle
        case recording
        case transcribing
        case done
        case error(String)
    }

    let recorder = AudioRecorderService()
    private var whisper: WhisperService?
    private var viewContext: NSManagedObjectContext?

    func setup(context: NSManagedObjectContext) {
        self.viewContext = context
        do {
            whisper = try WhisperService()
        } catch {
            state = .error("Impossible de charger le modèle Whisper")
        }
    }

    func toggleRecording() {
        if recorder.isRecording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        do {
            try recorder.startRecording()
            state = .recording
            observeRecorder()
        } catch {
            state = .error("Erreur micro : \(error.localizedDescription)")
        }
    }

    private func observeRecorder() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in
                self.elapsedTime = self.recorder.elapsedTime
                self.audioLevels = self.recorder.audioLevels
                if !self.recorder.isRecording && self.state == .recording {
                    timer.invalidate()
                    self.stopAndTranscribe()
                }
            }
        }
    }

    private func stopAndTranscribe() {
        guard let audioURL = recorder.currentFileURL else { return }
        recorder.stopRecording()
        state = .transcribing

        Task {
            do {
                guard let whisper else { throw WhisperService.WhisperError.initFailed }
                let text = try await whisper.transcribe(audioURL: audioURL)
                transcription = text
                try saveEntry(audioURL: audioURL, transcription: text)
                state = .done
            } catch {
                state = .error("Transcription échouée : \(error.localizedDescription)")
            }
        }
    }

    private func saveEntry(audioURL: URL, transcription: String) throws {
        guard let viewContext else { return }
        let entry = EntreeVocale(context: viewContext)
        entry.id = UUID()
        entry.dateEnregistrement = Date()
        entry.dureeSecondes = elapsedTime
        entry.transcriptionBrute = transcription
        entry.cheminAudio = audioURL.lastPathComponent
        try viewContext.save()
    }

    func reset() {
        state = .idle
        transcription = ""
        elapsedTime = 0
        audioLevels = Array(repeating: 0, count: 40)
    }

    var formattedTime: String {
        let mins = Int(elapsedTime) / 60
        let secs = Int(elapsedTime) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var remainingTime: String {
        let remaining = max(0, AudioRecorderService.maxDuration - elapsedTime)
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

extension RecordingViewModel.RecordingState: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording),
             (.transcribing, .transcribing), (.done, .done):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}
