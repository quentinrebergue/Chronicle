import AVFoundation
import Combine

final class AudioRecorderService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 40)

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var levelTimer: Timer?

    static let maxDuration: TimeInterval = 120 // 2 min

    var currentFileURL: URL? { recorder?.url }
    private var sessionReady = false

    func prepareSession() {
        Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.record, mode: .default)
            try? session.setActive(true)
            await MainActor.run { self.sessionReady = true }
            print("🎤 Session audio prête")
        }
    }

    func startRecording() throws {
        if !sessionReady {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        }

        let url = Self.newRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        recorder?.delegate = self
        recorder?.record(forDuration: Self.maxDuration)

        isRecording = true
        elapsedTime = 0

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsedTime = self.recorder?.currentTime ?? 0
            if self.elapsedTime >= Self.maxDuration {
                self.stopRecording()
            }
        }

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let normalized = max(0, min(1, (power + 50) / 50))
            self.audioLevels.removeFirst()
            self.audioLevels.append(normalized)
        }
    }

    func stopRecording() {
        recorder?.stop()
        timer?.invalidate()
        levelTimer?.invalidate()
        timer = nil
        levelTimer = nil
        isRecording = false
    }

    func deactivateSession() {
        // Ne pas désactiver — la réactivation prend ~7 secondes
    }

    private static func newRecordingURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = "chronicle_\(Int(Date().timeIntervalSince1970)).wav"
        return dir.appendingPathComponent(filename)
    }
}

extension AudioRecorderService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        isRecording = false
        timer?.invalidate()
        levelTimer?.invalidate()
    }
}
