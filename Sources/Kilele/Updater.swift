import AppKit

/// Updates from GitHub releases of Kimina-Santuri/kilele (made by scripts/release.sh, with Kilele.zip attached).
/// It checks once a day: through GitHub's public API if the repo is public, otherwise through the gh command-line
/// tool's existing login. An update is installed only if its code signature matches this copy's (same identifier
/// and signing certificate), so only builds from the same signing identity can replace it.
final class Updater: ObservableObject {
    @Published private(set) var available: String?   // e.g. "0.3.0"
    @Published private(set) var status = ""

    private static let repo = "Kimina-Santuri/kilele"
    private let queue = DispatchQueue(label: "kilele.updater")
    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.check() }
        Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in self?.check() }
    }

    func check() {
        queue.async { [weak self] in
            guard let self, let tag = self.latestTag() else { return }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            DispatchQueue.main.async { self.available = Self.newer(version, than: self.current) ? version : nil }
        }
    }

    func install() {
        guard let version = available else { return }
        status = "Downloading \(version)…"
        queue.async { [weak self] in
            guard let self else { return }
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("kilele-update-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: work) }
            let zip = work.appendingPathComponent("Kilele.zip")
            guard self.download(tag: "v" + version, to: zip),
                  Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path]).status == 0 else { return self.report("Couldn't download the update.") }
            let fresh = work.appendingPathComponent("Kilele.app")
            guard Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", fresh.path]).status == 0,
                  Self.requirement(fresh.path) != nil, Self.requirement(fresh.path) == Self.requirement(Bundle.main.bundlePath) else {
                return self.report("The update isn't signed like this copy of Kilele, so it wasn't installed.")
            }
            let installed = URL(fileURLWithPath: Bundle.main.bundlePath)
            do {
                try FileManager.default.trashItem(at: installed, resultingItemURL: nil)
                try FileManager.default.copyItem(at: fresh, to: installed)
            } catch { return self.report("Couldn't replace Kilele: \(error.localizedDescription)") }
            // Start the new copy once this one has quit.
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = ["-c", "sleep 1; open \"$0\"", installed.path]
            try? relaunch.run()
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func report(_ message: String) { DispatchQueue.main.async { self.status = message } }

    private func latestTag() -> String? {
        let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
        if let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = json["tag_name"] as? String { return tag }
        guard let gh = Self.gh else { return nil }
        let out = Self.run(gh, ["release", "view", "--repo", Self.repo, "--json", "tagName", "-q", ".tagName"])
        let tag = out.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.status == 0 && !tag.isEmpty ? tag : nil
    }

    private func download(tag: String, to zip: URL) -> Bool {
        let url = URL(string: "https://github.com/\(Self.repo)/releases/download/\(tag)/Kilele.zip")!
        if let data = try? Data(contentsOf: url), data.count > 1000, (try? data.write(to: zip)) != nil { return true }
        guard let gh = Self.gh else { return false }
        return Self.run(gh, ["release", "download", tag, "--repo", Self.repo, "--pattern", "Kilele.zip", "--dir", zip.deletingLastPathComponent().path]).status == 0
    }

    private static var gh: String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The code signature's designated requirement ("identifier … and certificate leaf = …").
    private static func requirement(_ path: String) -> String? {
        let out = run("/usr/bin/codesign", ["-d", "-r-", path])
        return out.output.components(separatedBy: "\n").first { $0.hasPrefix("designated =>") }
    }

    private static func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = pipe
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env
        guard (try? p.run()) != nil else { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
