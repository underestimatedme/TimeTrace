import Foundation

/// JSON file persistence in Application Support (atomic writes).
final class StateStore {
    static let fileName = "keji-state.json"

    let url: URL

    init(url: URL? = nil, fileName: String = StateStore.fileName) {
        if let url {
            self.url = url
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let dir = base.appendingPathComponent("KeJi", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.url = dir.appendingPathComponent(fileName)
        }
    }

    func load() -> PersistedState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONCoding.decoder.decode(PersistedState.self, from: data)
    }

    func save(_ state: PersistedState) {
        do {
            let data = try JSONCoding.encoder.encode(state)
            try data.write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            print("[StateStore] save failed: \(error)")
            #endif
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
