import AppKit

/// What's playing. Normally anything on the Mac, browsers included, through the bundled mediaremote-adapter.
/// If that's missing or stops working, Music and Spotify only: both announce track and play-state changes publicly,
/// and artwork and the play/skip buttons use AppleScript (macOS asks once per app).
final class NowPlaying: ObservableObject {
    enum Player: String {
        case music = "Music", spotify = "Spotify"
        var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
        var announcement: String { self == .music ? "com.apple.Music.playerInfo" : "com.spotify.client.PlaybackStateChanged" }
    }

    @Published private(set) var player: Player?
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var source = ""   // the app it's playing in, e.g. "Google Chrome"

    var hasMedia: Bool { !title.isEmpty }

    private let scripts = DispatchQueue(label: "kilele.nowplaying")
    private var artworkKey = ""
    private var adapter: MediaRemoteAdapter?
    private var fallbackStarted = false

    init() {
        guard let adapter = MediaRemoteAdapter.bundled() else { startFallback(); return }
        self.adapter = adapter
        adapter.onUpdate = { [weak self] info in
            guard let self, self.adapter != nil else { return }
            self.title = info?.title ?? ""
            self.artist = info?.artist ?? ""
            self.isPlaying = info?.playing ?? false
            self.artwork = info?.artwork
            self.source = info?.source ?? ""
        }
        adapter.onFailure = { [weak self] in
            self?.adapter = nil
            self?.startFallback()
        }
        adapter.start()
    }

    private func startFallback() {
        guard !fallbackStarted else { return }
        fallbackStarted = true
        for p in [Player.music, .spotify] {
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name(p.announcement), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                self?.apply(p, state: info["Player State"] as? String ?? "", title: info["Name"] as? String ?? "", artist: info["Artist"] as? String ?? "")
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let self, let p = self.player, app?.bundleIdentifier == p.bundleID { self.apply(p, state: "Stopped", title: "", artist: "") }
        }
        // Something may already be playing when Kilele starts. Only ask players that are open, so none get launched.
        for p in [Player.music, .spotify] where isRunning(p) {
            scripts.async { [weak self] in
                let r = Self.run("""
                tell application "\(p.rawValue)"
                    if player state is playing then return {"Playing", name of current track, artist of current track}
                end tell
                return {"", "", ""}
                """)
                let parts = (1...3).map { r?.atIndex($0)?.stringValue ?? "" }
                DispatchQueue.main.async { if parts[0] == "Playing" { self?.apply(p, state: "Playing", title: parts[1], artist: parts[2]) } }
            }
        }
    }

    func playPause() { if let adapter { adapter.send(2) } else { command("playpause") } }
    func next() { if let adapter { adapter.send(4) } else { command("next track") } }
    func previous() { if let adapter { adapter.send(5) } else { command("previous track") } }

    private func apply(_ p: Player, state: String, title: String, artist: String) {
        switch state {
        case "Playing":
            player = p
            source = p.rawValue
            isPlaying = true
            if !title.isEmpty { self.title = title; self.artist = artist }
            loadArtwork(p)
        case "Paused":
            if player == p { isPlaying = false }
        default: // Stopped, or the player quit
            guard player == p else { return }
            player = nil; isPlaying = false; self.title = ""; self.artist = ""; artwork = nil; artworkKey = ""; source = ""
        }
    }

    private func loadArtwork(_ p: Player) {
        let key = "\(p.rawValue)|\(title)|\(artist)"
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        scripts.async { [weak self] in
            var image: NSImage?
            if p == .music {
                if let data = Self.run("tell application \"Music\" to return raw data of artwork 1 of current track")?.data { image = NSImage(data: data) }
            } else if let link = Self.run("tell application \"Spotify\" to return artwork url of current track")?.stringValue,
                      let url = URL(string: link), url.scheme == "https", let data = try? Data(contentsOf: url) {
                image = NSImage(data: data)
            }
            DispatchQueue.main.async { if self?.artworkKey == key { self?.artwork = image } }
        }
    }

    private func command(_ verb: String) {
        guard let p = player else { return }
        scripts.async { _ = Self.run("tell application \"\(p.rawValue)\" to \(verb)") }
    }

    private func isRunning(_ p: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: p.bundleID).isEmpty
    }

    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}
