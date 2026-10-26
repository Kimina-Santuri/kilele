import AppKit

/// Kilele's link to the Tsuzuri notes workspace (~/Documents/notes): capture to Inbox, to-dos due today, Tasks cards in
/// progress, shelf files into notes, and opening Tsuzuri in iTerm. Files are written the way Tsuzuri writes them
/// (checkboxes, Inbox list items, assets/ links), and notes-sync runs shortly after a change so the phone gets it.
final class Notes: ObservableObject {
    struct Todo: Identifiable, Equatable {
        let id: String
        let file: URL
        let line: Int      // 1-based
        let text: String   // without the checkbox
        let note: String   // note name, for "open in Tsuzuri"
        let due: Date?
    }

    struct Card: Identifiable, Equatable {
        let id: String
        let title: String
        let note: String?  // first [[link]] in the card's description
    }

    @Published private(set) var todos: [Todo] = []
    @Published private(set) var inProgress: [Card] = []
    @Published private(set) var status = ""
    @Published var draft = ""
    /// Where captures, voice memos and shelf files go: Inbox, or the Log section of today's journal note.
    enum Target: String { case inbox, journal }
    @Published var target = Target(rawValue: UserDefaults.standard.string(forKey: "captureTarget") ?? "") ?? .inbox {
        didSet { UserDefaults.standard.set(target.rawValue, forKey: "captureTarget") }
    }

    // KILELE_NOTES points Kilele at another folder (used to test against a copy of the notes).
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["KILELE_NOTES"] ?? NSHomeDirectory() + "/Documents/notes")
    private var inbox: URL { root.appendingPathComponent("Inbox.md") }
    private let io = DispatchQueue(label: "kilele.notes")
    private var syncWork: DispatchWorkItem?
    private static let maxAttachment = 25 * 1024 * 1024 // notes sync to the phone through GitHub; keep them light

    // Same pattern as Tsuzuri's core.todoRe.
    private static let checkbox = try! NSRegularExpression(pattern: #"^(\s*[-*+]\s+\[)([ xX])(\]\s?)(.*)$"#)
    private static let dueDate = try! NSRegularExpression(pattern: #"@(\d{4}-\d{2}-\d{2})"#)
    private static let wikiLink = try! NSRegularExpression(pattern: #"\[\[([^\]|#]+)"#)

    /// Whether the Tsuzuri workspace is there. Checked off the main thread: the first look inside ~/Documents makes
    /// macOS ask for permission, and waiting on that answer while drawing would leave the notch blank.
    @Published private(set) var available = false

    init() {
        io.async { [weak self] in
            guard let self else { return }
            let found = FileManager.default.fileExists(atPath: self.inbox.path)
            DispatchQueue.main.async { self.available = found }
        }
    }

    // MARK: Reading

    func reload() {
        io.async { [weak self] in
            guard let self else { return }
            // Also re-check the workspace: access to Documents may have been allowed since launch.
            let found = FileManager.default.fileExists(atPath: self.inbox.path)
            let todos = found ? self.scanTodos() : [], cards = found ? self.scanInProgress() : []
            DispatchQueue.main.async { self.available = found; self.todos = todos; self.inProgress = cards }
        }
    }

    /// Unticked to-dos with an @date of today or earlier, soonest first (Templates skipped, like Tsuzuri).
    private func scanTodos() -> [Todo] {
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        var found: [Todo] = []
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in walk {
            if url.lastPathComponent == "Templates" { walk.skipDescendants(); continue }
            guard url.pathExtension == "md", let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var fenced = false
            for (i, line) in text.components(separatedBy: "\n").enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fenced.toggle(); continue }
                guard !fenced, let item = Self.uncheckedText(line), !item.isEmpty,
                      let match = Self.dueDate.firstMatch(in: item, range: NSRange(item.startIndex..., in: item)),
                      let range = Range(match.range(at: 1), in: item), let due = day.date(from: String(item[range])), due < endOfToday else { continue }
                found.append(Todo(id: "\(url.path):\(i + 1)", file: url, line: i + 1, text: item, note: url.deletingPathExtension().lastPathComponent, due: due))
            }
        }
        return found.sorted { ($0.due ?? .distantFuture, $0.note) < ($1.due ?? .distantFuture, $1.note) }
    }

    /// Cards under "## In progress" in the ```board block of Tasks.md.
    private func scanInProgress() -> [Card] {
        guard let text = try? String(contentsOf: root.appendingPathComponent("Tasks.md"), encoding: .utf8) else { return [] }
        var cards: [Card] = [], inBoard = false, inSection = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inBoard = trimmed.hasPrefix("```board"); inSection = false; continue }
            guard inBoard else { continue }
            if trimmed.hasPrefix("## ") { inSection = trimmed.dropFirst(3).lowercased() == "in progress"; continue }
            guard inSection else { continue }
            if line.hasPrefix("- ") {
                let title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                cards.append(Card(id: "\(cards.count):\(title)", title: title, note: Self.firstLink(title)))
            } else if let last = cards.last, last.note == nil, let link = Self.firstLink(line) {
                cards[cards.count - 1] = Card(id: last.id, title: last.title, note: link)
            }
        }
        return cards
    }

    private static func uncheckedText(_ line: String) -> String? {
        let ns = line as NSString
        guard let m = checkbox.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)), ns.substring(with: m.range(at: 2)) == " " else { return nil }
        return ns.substring(with: m.range(at: 4)).trimmingCharacters(in: .whitespaces)
    }

    private static func firstLink(_ text: String) -> String? {
        guard let m = wikiLink.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let r = Range(m.range(at: 1), in: text) else { return nil }
        return text[r].trimmingCharacters(in: .whitespaces)
    }

    // MARK: Writing

    /// Ticks a to-do in its note. The note is re-read first: if the phone (or Tsuzuri) moved the line, the same
    /// unticked text is found again; if it's gone, nothing is written.
    func tick(_ todo: Todo) {
        todos.removeAll { $0.id == todo.id }
        io.async { [weak self] in
            guard let self, let text = try? String(contentsOf: todo.file, encoding: .utf8) else { return }
            var lines = text.components(separatedBy: "\n")
            let candidates = [todo.line - 1] + lines.indices.filter { $0 != todo.line - 1 }
            guard let i = candidates.first(where: { lines.indices.contains($0) && Self.uncheckedText(lines[$0]) == todo.text }) else {
                self.report("That to-do changed in the note, so it wasn't ticked."); self.reload(); return
            }
            let ns = lines[i] as NSString
            let m = Self.checkbox.firstMatch(in: lines[i], range: NSRange(location: 0, length: ns.length))!
            lines[i] = ns.replacingCharacters(in: m.range(at: 2), with: "x")
            self.write(lines.joined(separator: "\n"), to: todo.file, done: "Ticked in \(todo.note)")
        }
    }

    /// Adds the typed text as a new line in Inbox.md.
    func capture() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        add("- " + text.replacingOccurrences(of: "\n", with: " "))
    }

    /// A finished focus session, in today's journal Log: "- 14:00–14:25 · 25 min focus: label".
    func logFocus(start: Date, end: Date, label: String) {
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        let minutes = max(1, Int((end.timeIntervalSince(start) / 60).rounded()))
        addToJournal("- \(clock.string(from: start))–\(clock.string(from: end)) · \(minutes) min focus" + (label.isEmpty ? "" : ": \(label)"), done: "Focus session logged in today's journal")
    }

    private func add(_ item: String, file: String? = nil) {
        switch target {
        case .inbox: addToInbox(item, done: file.map { "Added \($0) to your notes (linked in Inbox)" } ?? "Added to Inbox")
        case .journal: addToJournal(item, done: file.map { "Added \($0) to your notes (linked in today's journal)" } ?? "Added to today's journal")
        }
    }

    /// Copies a file into notes/assets (as Tsuzuri's attach does) and links it from Inbox or today's journal.
    /// `moving` removes the original afterwards (voice memos recorded to a temporary file).
    func attach(_ file: URL, moving: Bool = false) {
        io.async { [weak self] in
            guard let self else { return }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= Self.maxAttachment else { self.report("\(file.lastPathComponent) is over 25 MB, too big to sync to your phone."); return }
            let assets = self.root.appendingPathComponent("assets"), ext = file.pathExtension, stem = file.deletingPathExtension().lastPathComponent
            var target = assets.appendingPathComponent(file.lastPathComponent)
            var n = 2
            while FileManager.default.fileExists(atPath: target.path) {
                target = assets.appendingPathComponent(ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"); n += 1
            }
            do {
                try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: file, to: target)
            } catch { self.report("Couldn't copy \(file.lastPathComponent) into your notes."); return }
            if moving { try? FileManager.default.removeItem(at: file) }
            var link = "assets/" + target.lastPathComponent
            if link.rangeOfCharacter(from: CharacterSet(charactersIn: " ()")) != nil { link = "<\(link)>" }
            let kind = ext.lowercased()
            let line: String
            if ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "heic", "avif"].contains(kind) { line = "![\(stem)](\(link))" }
            else if ["mp4", "mov", "webm", "mkv", "avi", "m4v"].contains(kind) { line = "[▶ \(stem)](\(link))" }
            else if ["mp3", "wav", "m4a", "ogg", "flac", "aac"].contains(kind) { line = "[♪ \(stem)](\(link))" }
            else { line = "[📎 \(target.lastPathComponent)](\(link))" }
            DispatchQueue.main.async { self.add("- " + line, file: target.lastPathComponent) }
        }
    }

    /// Inbox keeps an empty "- " bullet ready for typing; a new item fills that, otherwise goes after the last item.
    private func addToInbox(_ item: String, done: String) {
        io.async { [weak self] in
            guard let self else { return }
            guard let text = try? String(contentsOf: self.inbox, encoding: .utf8) else { self.report("Couldn't open Inbox.md in your notes."); return }
            var lines = text.components(separatedBy: "\n")
            if let i = lines.lastIndex(where: { $0.hasPrefix("- ") || $0 == "-" }) {
                if lines[i].trimmingCharacters(in: .whitespaces) == "-" { lines[i] = item } else { lines.insert(item, at: i + 1) }
            } else {
                while lines.last == "" { lines.removeLast() }
                lines += ["", item, ""]
            }
            self.write(lines.joined(separator: "\n"), to: self.inbox, done: done)
        }
    }

    /// Today's journal note, created the way Tsuzuri creates it (`tsuzuri today -n`: template, carried-over to-dos,
    /// link from Journal.md). If Tsuzuri isn't there, a plain note with a Log section.
    private func todaysJournal() -> URL? {
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        let url = root.appendingPathComponent("Journal/\(day.string(from: Date())).md")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let tsuzuri = NSHomeDirectory() + "/bin/tsuzuri"
        if FileManager.default.isExecutableFile(atPath: tsuzuri) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tsuzuri)
            p.arguments = ["today", "-n"]
            var env = ProcessInfo.processInfo.environment
            env["TSUZURI_WORKSPACE"] = root.path
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/bin:/usr/bin:/bin"
            p.environment = env
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            if (try? p.run()) != nil { p.waitUntilExit() }
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "# \(day.string(from: Date()))\n\nPart of [[Journal]]\n\n## Log\n- \n".write(to: url, atomically: true, encoding: .utf8)
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Into the "## Log" section of today's journal: fills its empty "- " bullet, otherwise goes after its last item.
    private func addToJournal(_ item: String, done: String) {
        io.async { [weak self] in
            guard let self else { return }
            guard let url = self.todaysJournal(), let text = try? String(contentsOf: url, encoding: .utf8) else { self.report("Couldn't open today's journal note."); return }
            var lines = text.components(separatedBy: "\n")
            if let log = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == "## log" }) {
                let end = lines[(log + 1)...].firstIndex(where: { $0.hasPrefix("#") }) ?? lines.count
                if let last = lines[(log + 1)..<end].lastIndex(where: { $0.hasPrefix("- ") || $0 == "-" }) {
                    if lines[last].trimmingCharacters(in: .whitespaces) == "-" { lines[last] = item } else { lines.insert(item, at: last + 1) }
                } else {
                    lines.insert(item, at: log + 1)
                }
            } else {
                while lines.last == "" { lines.removeLast() }
                lines += ["", "## Log", item, ""]
            }
            self.write(lines.joined(separator: "\n"), to: url, done: done)
        }
    }

    private func write(_ text: String, to url: URL, done: String) {
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { report("Couldn't save \(url.lastPathComponent)."); return }
        report(done)
        reload()
        scheduleSync()
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { self.status = message }
    }

    /// Runs ~/bin/notes-sync 15 s after the last change (Tsuzuri also syncs on its own when it's open).
    private func scheduleSync() {
        DispatchQueue.main.async {
            self.syncWork?.cancel()
            let work = DispatchWorkItem {
                let script = NSHomeDirectory() + "/bin/notes-sync"
                guard FileManager.default.isExecutableFile(atPath: script) else { return }
                let p = Process()
                p.executableURL = URL(fileURLWithPath: script)
                p.arguments = [self.root.path]
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                p.environment = env
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                try? p.run()
            }
            self.syncWork = work
            DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: work)
        }
    }

    // MARK: Tsuzuri

    /// Opens Tsuzuri in a new iTerm window (Terminal if iTerm isn't there), through your shell so ~/bin and the
    /// notes workspace setting from .zshrc apply. `args` is "today", a note name, or empty for Home.
    func openTsuzuri(_ args: String = "") {
        let command = args.isEmpty ? "tsuzuri" : "tsuzuri " + Self.shellQuote(args)
        let quoted = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let iTerm = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").isEmpty
            || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil
        let source = iTerm ? """
            tell application "iTerm"
                activate
                set w to (create window with default profile)
                tell current session of w to write text "\(quoted)"
            end tell
            """ : """
            tell application "Terminal"
                activate
                do script "\(quoted)"
            end tell
            """
        DispatchQueue.global().async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if error != nil { self.report("Couldn't open Tsuzuri. Allow Kilele to control \(iTerm ? "iTerm" : "Terminal") in System Settings › Privacy & Security › Automation.") }
        }
    }

    private static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
