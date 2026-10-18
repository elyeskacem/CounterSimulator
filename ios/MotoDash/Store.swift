import Foundation

/// Persistence: two JSON files in Application Support (not Caches, so iOS never
/// purges them; they are also part of the iCloud/Finder backup of the phone).
/// Writes are atomic and stay readable while the phone is locked, which matters
/// because the app keeps saving in the background during a ride.
final class Store {
    static let shared = Store()

    private let directory: URL
    private let queue = DispatchQueue(label: "motodash.store", qos: .utility)

    private var stateURL: URL { directory.appendingPathComponent("state.json") }
    private var eventsURL: URL { directory.appendingPathComponent("events.json") }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("MotoDash", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func loadState() -> AppState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(AppState.self, from: data)
    }

    func loadEvents() -> [RideEvent] {
        guard let data = try? Data(contentsOf: eventsURL) else { return [] }
        return (try? JSONDecoder().decode([RideEvent].self, from: data)) ?? []
    }

    func save(state: AppState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        write(data, to: stateURL)
    }

    func save(events: [RideEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        write(data, to: eventsURL)
    }

    /// Blocks until queued writes are on disk (used when the app is about to be suspended).
    func flush() {
        queue.sync {}
    }

    private func write(_ data: Data, to url: URL) {
        queue.async {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
