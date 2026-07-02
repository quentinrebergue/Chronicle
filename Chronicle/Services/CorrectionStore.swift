import Foundation

final class CorrectionStore {
    static let shared = CorrectionStore()

    private var corrections: [String: String] = [:]
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("entity_corrections.json")
        load()
    }

    func addCorrection(from original: String, to corrected: String) {
        let key = original.lowercased()
        corrections[key] = corrected
        save()
        AppLogger.log("📝 Correction enregistrée: \"\(original)\" → \"\(corrected)\"")
    }

    func correctedName(for text: String) -> String? {
        corrections[text.lowercased()]
    }

    var allCorrections: [String: String] { corrections }

    func clearAll() {
        corrections.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        corrections = dict
        if !corrections.isEmpty {
            AppLogger.log("📝 \(corrections.count) corrections chargées")
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(corrections) else { return }
        try? data.write(to: fileURL)
    }
}
