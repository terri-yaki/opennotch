import AppKit

/// What Apple Music is playing, plus time-synced lyrics.
///
/// Track changes arrive via Music's `com.apple.Music.playerInfo` distributed notification.
/// Position and artwork come from AppleScript, which macOS gates behind a one-time
/// "OpenNotch wants to control Music" prompt. AppleScript only runs while Music is already
/// open, so OpenNotch never launches it. Lyrics come from LRCLIB (lrclib.net), a free,
/// keyless lyrics database: only the track title, artist, album and duration are sent.
@MainActor
final class MusicStore: ObservableObject {
    static let shared = MusicStore()

    struct LyricLine: Identifiable, Equatable {
        let id: Int
        let time: Double // seconds
        let text: String
    }

    enum Lyrics: Equatable {
        case none, loading, notFound
        case synced([LyricLine])
        case plain(String)
    }

    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var hasTrack = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var lyrics: Lyrics = .none

    /// Last known position and when we learned it; `position(at:)` extrapolates while playing.
    private var positionBase: Double = 0
    private var positionStamp = Date()

    private let scriptQueue = DispatchQueue(label: "OpenNotch.music.applescript")
    private var pollTimer: Timer?
    private var trackKey = ""
    private var lyricsCache: [String: Lyrics] = [:]
    private static let bundleID = "com.apple.Music"

    private init() {}

    func start() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Keep position honest after seeks; cheap, and skipped entirely when Music isn't open.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.refresh()
            }
        }
        refresh()
    }

    func position(at date: Date) -> Double {
        let elapsed = isPlaying ? date.timeIntervalSince(positionStamp) : 0
        return min(positionBase + elapsed, duration > 0 ? duration : .infinity)
    }

    // MARK: Controls

    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    private func command(_ verb: String) {
        guard musicRunning else { return }
        run("tell application \"Music\" to \(verb)") { [weak self] _ in self?.refresh() }
    }

    // MARK: Refresh

    private var musicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    private func refresh() {
        guard musicRunning else { clear(); return }
        let script = """
        tell application "Music"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {player state as string, name of t, artist of t, album of t, duration of t, player position}
        end tell
        """
        run(script) { [weak self] result in
            guard let self else { return }
            guard let result, result.numberOfItems >= 6 else { self.clear(); return }
            let state = result.atIndex(1)?.stringValue ?? ""
            let title = result.atIndex(2)?.stringValue ?? ""
            let artist = result.atIndex(3)?.stringValue ?? ""
            let album = result.atIndex(4)?.stringValue ?? ""
            let duration = result.atIndex(5)?.doubleValue ?? 0
            let position = result.atIndex(6)?.doubleValue ?? 0

            self.hasTrack = true
            self.isPlaying = state == "playing"
            self.positionBase = position
            self.positionStamp = Date()

            let key = "\(title)\u{1}\(artist)\u{1}\(album)"
            guard key != self.trackKey else { return }
            self.trackKey = key
            self.title = title
            self.artist = artist
            self.album = album
            self.duration = duration
            self.loadArtwork()
            self.loadLyrics(key: key)
        }
    }

    private func clear() {
        hasTrack = false
        isPlaying = false
        trackKey = ""
        title = ""; artist = ""; album = ""
        artwork = nil
        lyrics = .none
    }

    private func loadArtwork() {
        artwork = nil
        let key = trackKey
        run("tell application \"Music\" to get raw data of artwork 1 of current track") { [weak self] result in
            guard let self, self.trackKey == key, let data = result?.data else { return }
            self.artwork = NSImage(data: data)
        }
    }

    // MARK: Lyrics

    private func loadLyrics(key: String) {
        if let cached = lyricsCache[key] { lyrics = cached; return }
        lyrics = .loading
        let (title, artist, album, duration) = (self.title, self.artist, self.album, self.duration)

        Task {
            let found = await Self.fetchLyrics(title: title, artist: artist, album: album, duration: duration)
            guard self.trackKey == key else { return }
            if let found {
                self.lyricsCache[key] = found
                self.lyrics = found
            } else {
                self.fetchEmbeddedLyrics(key: key)
            }
        }
    }

    /// Fallback: lyrics stored in the track itself (plain text, no timing).
    private func fetchEmbeddedLyrics(key: String) {
        run("tell application \"Music\" to get lyrics of current track") { [weak self] result in
            guard let self, self.trackKey == key else { return }
            let text = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let value: Lyrics = text.isEmpty ? .notFound : .plain(text)
            self.lyricsCache[key] = value
            self.lyrics = value
        }
    }

    private nonisolated static func fetchLyrics(title: String, artist: String, album: String,
                                                duration: Double) async -> Lyrics? {
        struct Hit: Decodable { let syncedLyrics: String?; let plainLyrics: String? }

        func get(_ path: String, _ query: [URLQueryItem]) async -> Data? {
            var components = URLComponents(string: "https://lrclib.net/api/\(path)")!
            components.queryItems = query
            var request = URLRequest(url: components.url!, timeoutInterval: 10)
            request.setValue("OpenNotch/0.1 (macOS notch utility)", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        }

        // Exact match first (best timing), then a looser search.
        var hits: [Hit] = []
        if let data = await get("get", [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
        ]), let hit = try? JSONDecoder().decode(Hit.self, from: data) {
            hits.append(hit)
        }
        if !hits.contains(where: { $0.syncedLyrics?.isEmpty == false }),
           let data = await get("search", [URLQueryItem(name: "track_name", value: title),
                                           URLQueryItem(name: "artist_name", value: artist)]),
           let results = try? JSONDecoder().decode([Hit].self, from: data) {
            hits += results
        }

        if let synced = hits.lazy.compactMap(\.syncedLyrics).first(where: { !$0.isEmpty }) {
            let lines = parseLRC(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = hits.lazy.compactMap(\.plainLyrics).first(where: { !$0.isEmpty }) {
            return .plain(plain)
        }
        return nil
    }

    /// Parses "[mm:ss.xx] text" lines; lines with several stamps are repeated at each.
    nonisolated static func parseLRC(_ lrc: String) -> [LyricLine] {
        var timed: [(Double, String)] = []
        for raw in lrc.split(separator: "\n", omittingEmptySubsequences: false) {
            var rest = Substring(raw)
            var stamps: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                let parts = tag.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                    stamps.append(m * 60 + s)
                }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for stamp in stamps { timed.append((stamp, text)) }
        }
        return timed.sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }

    // MARK: AppleScript

    /// Runs on a private serial queue (Music can take a moment to answer) and delivers the
    /// result on the main actor.
    private func run(_ source: String, completion: @escaping @MainActor (NSAppleEventDescriptor?) -> Void) {
        scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let value = error == nil ? result : nil
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(value) } }
        }
    }
}
