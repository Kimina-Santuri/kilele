import AppKit

/// What's playing anywhere on the Mac (browsers included), through the open-source mediaremote-adapter
/// (github.com/ungive/mediaremote-adapter, BSD-3, vendored in Vendor/ and bundled in Resources/MediaRemoteAdapter).
/// macOS only lets its own binaries read system Now Playing, so the adapter's script runs under /usr/bin/perl and
/// loads the adapter framework; `stream` prints one JSON line per change, and `send` controls the player.
final class MediaRemoteAdapter {
    struct Info {
        var title: String
        var artist: String
        var playing: Bool
        var artwork: NSImage?
        var source: String   // the app's name, e.g. "Google Chrome"
    }

    /// Called on the main queue: the current media, or nil when nothing is reporting.
    var onUpdate: (Info?) -> Void = { _ in }
    /// Called on the main queue if the adapter can't run at all, so Kilele falls back to Music/Spotify only.
    var onFailure: () -> Void = {}

    private let script: URL
    private let framework: URL
    private var process: Process?
    private var buffer = Data()
    private var state: [String: Any] = [:]
    private var artwork: NSImage?
    private var everReceived = false
    private var restarts = 0
    private var stopping = false
    private let parse = DispatchQueue(label: "kilele.mediaremote")

    /// The adapter bundled in the app, if the build included it.
    static func bundled() -> MediaRemoteAdapter? {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("MediaRemoteAdapter") else { return nil }
        let script = dir.appendingPathComponent("mediaremote-adapter.pl"), framework = dir.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: script.path), FileManager.default.fileExists(atPath: framework.path) else { return nil }
        return MediaRemoteAdapter(script: script, framework: framework)
    }

    private init(script: URL, framework: URL) {
        self.script = script
        self.framework = framework
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() }
    }

    func start() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script.path, framework.path, "stream", "--debounce=150"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.parse.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.ended() } }
        do { try p.run(); process = p } catch { onFailure() }
    }

    func stop() {
        stopping = true
        process?.terminate()
    }

    /// MediaRemote command IDs: 2 toggle play/pause, 4 next track, 5 previous track.
    func send(_ command: Int) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script.path, framework.path, "send", String(command)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// The stream died: start it again if it had been working (a few times), otherwise give up and fall back.
    private func ended() {
        process = nil
        guard !stopping else { return }
        if everReceived && restarts < 5 {
            restarts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
        } else {
            onFailure()
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = json["payload"] as? [String: Any] else { continue }
            everReceived = true
            // A full payload replaces what we know; a diff updates it (a null value means the key went away).
            if json["diff"] as? Bool == true {
                for (key, value) in payload { if value is NSNull { state.removeValue(forKey: key) } else { state[key] = value } }
            } else {
                state = payload
            }
            if payload.keys.contains("artworkData") || json["diff"] as? Bool != true {
                artwork = (state["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }.flatMap(NSImage.init(data:))
            }
            let info = currentInfo()
            DispatchQueue.main.async { [weak self] in self?.onUpdate(info) }
        }
    }

    private func currentInfo() -> Info? {
        guard let title = state["title"] as? String, !title.isEmpty else { return nil }
        // Web players report the browser as the parent app.
        let app = (state["parentApplicationBundleIdentifier"] as? String) ?? (state["bundleIdentifier"] as? String)
        return Info(title: title, artist: state["artist"] as? String ?? "", playing: state["playing"] as? Bool ?? false,
                    artwork: artwork, source: app.map(Self.appName) ?? "")
    }

    private static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return "" }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
