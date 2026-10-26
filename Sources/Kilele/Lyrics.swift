import Foundation

/// Synced lyrics from LRCLIB (lrclib.net: free, no account or key). Only the song's title, artist and length are sent.
/// Web players often put "Artist - Song (Official Video)" in the title, so that's tried as a second guess.
final class Lyrics: ObservableObject {
    struct Line: Equatable {
        let time: Double
        let text: String
    }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var searching = false
    @Published var enabled = UserDefaults.standard.object(forKey: "lyrics") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "lyrics"); if !enabled { lines = [] } }
    }

    private var key = ""

    func load(title: String, artist: String, duration: Double) {
        let key = "\(title)|\(artist)"
        guard enabled, !title.isEmpty, key != self.key else { return }
        self.key = key
        lines = []
        searching = true
        var guesses = [(title, artist)]
        if let dash = title.range(of: " - ") {
            guesses.append((Self.clean(String(title[dash.upperBound...])), Self.clean(String(title[..<dash.lowerBound]))))
        }
        Task {
            let found = await Self.lookup(guesses, duration: duration)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.key == key else { return }
                self.lines = found
                self.searching = false
            }
        }
    }

    private static func lookup(_ guesses: [(String, String)], duration: Double) async -> [Line] {
        for (title, artist) in guesses {
            let found = await fetch(title: title, artist: artist, duration: duration)
            if !found.isEmpty { return found }
        }
        return []
    }

    /// The line being sung at `time`, and the one after it.
    func current(at time: Double) -> (now: String, next: String) {
        guard let i = lines.lastIndex(where: { $0.time <= time + 0.3 }) else { return ("", lines.first?.text ?? "") }
        return (lines[i].text, i + 1 < lines.count ? lines[i + 1].text : "")
    }

    private static func fetch(title: String, artist: String, duration: Double) async -> [Line] {
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        get.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if duration > 0 { get.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        if let record = await json(get.url!) as? [String: Any], let synced = record["syncedLyrics"] as? String { return parse(synced) }
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        let results = await json(search.url!) as? [[String: Any]] ?? []
        guard let synced = results.compactMap({ $0["syncedLyrics"] as? String }).first else { return [] }
        return parse(synced)
    }

    private static func json(_ url: URL) async -> Any? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Kilele (github.com/Kimina-Santuri/kilele)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// LRC: "[01:23.45] words" per line.
    static func parse(_ lrc: String) -> [Line] {
        let pattern = try! NSRegularExpression(pattern: #"^\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$"#)
        return lrc.components(separatedBy: .newlines).compactMap { line in
            let ns = line as NSString
            guard let m = pattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0, seconds = Double(ns.substring(with: m.range(at: 2))) ?? 0
            return Line(time: minutes * 60 + seconds, text: ns.substring(with: m.range(at: 3)))
        }
    }

    /// "Song (Official Video) [4K]" → "Song"; "Artist VEVO" → "Artist".
    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*(VEVO|- Topic)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
