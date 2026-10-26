import AppKit
import SQLite3

/// One notification another app posted (a message, an email, a WhatsApp, …).
struct Alert: Identifiable, Equatable {
    let id: Data          // the notification's uuid
    let app: String       // bundle identifier, e.g. com.apple.MobileSMS
    let title: String
    let subtitle: String
    let body: String
    let date: Date
    let link: URL?        // where clicking takes you (Messages gives the conversation), else the app opens
}

/// Notifications from other apps, read from macOS's own notification record (the database Notification Center keeps,
/// `~/Library/Group Containers/group.com.apple.usernoted/db2/db`). Reading it needs access to other apps' data:
/// macOS asks once, or it's given under Full Disk Access. Kilele only reads it, never writes, and nothing leaves the Mac.
/// Notifications cleared in Notification Center (or read on the phone, for Messages) drop out here too.
///
/// Kilele can't stop macOS's own banners; per app, System Settings › Notifications › Alert style "None" does that
/// while keeping "Show in Notification Centre" on, so notifications are still recorded and shown here instead.
final class Alerts: ObservableObject {
    /// Last 24 hours, newest first, without muted apps or ones you've dismissed.
    @Published private(set) var items: [Alert] = []
    /// Apps that posted in the last week (for the Apps menu), by name.
    @Published private(set) var apps: [String] = []
    @Published private(set) var allowed = true
    @Published private(set) var muted: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "mutedAlertApps") ?? [])
    /// New notifications drop down from the notch.
    @Published var peeks = UserDefaults.standard.object(forKey: "alertPeeks") as? Bool ?? true {
        didSet { UserDefaults.standard.set(peeks, forKey: "alertPeeks") }
    }
    @Published private(set) var seenUntil = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "alertsSeenUntil"))
    var unread: Int { items.filter { $0.date > seenUntil }.count }
    var onNew: (Alert) -> Void = { _ in }

    private static let folder = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/"
    private let queue = DispatchQueue(label: "kilele.alerts")
    private var all: [Alert] = []
    private var known: Set<Data>?        // nil until the first read, so what's already there doesn't pop up
    private var dismissed: Set<Data> = Set((UserDefaults.standard.array(forKey: "dismissedAlerts") as? [Data]) ?? [])
    private var stamp = ""
    private var names: [String: String] = [:]
    private var icons: [String: NSImage] = [:]

    init() {
        // The database is written through its WAL file; look every 2 s and read only when something changed.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.publish() } // age out old ones
        poll()
    }

    private func poll() {
        queue.async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let stamp = ["db", "db-wal"].map { name -> String in
                let a = try? fm.attributesOfItem(atPath: Self.folder + name)
                return "\((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)/\(a?[.size] as? Int ?? 0)"
            }.joined(separator: "|")
            guard stamp != self.stamp else { return }
            let found = Self.read()
            if found != nil { self.stamp = stamp } // keep retrying while access is off
            DispatchQueue.main.async { self.take(found) }
        }
    }

    private func take(_ found: [Alert]?) {
        allowed = found != nil
        guard let found else { return }
        let fresh = known.map { k in found.filter { !k.contains($0.id) } } ?? []
        known = Set(found.map(\.id))
        all = found
        dismissed.formIntersection(known ?? [])
        publish()
        // Several at once (a burst, or the Mac waking): show the newest.
        if let newest = fresh.filter({ !isMuted($0.app) && $0.date > Date().addingTimeInterval(-120) && $0.app != Bundle.main.bundleIdentifier }).max(by: { $0.date < $1.date }) {
            onNew(newest)
        }
    }

    private func publish() {
        let day = Date().addingTimeInterval(-86_400), week = Date().addingTimeInterval(-7 * 86_400)
        items = all.filter { $0.date > day && !isMuted($0.app) && !dismissed.contains($0.id) && $0.app != Bundle.main.bundleIdentifier }
            .sorted { $0.date > $1.date }
        apps = Array(Set(all.filter { $0.date > week }.map(\.app))).sorted { name($0) < name($1) }
    }

    func isMuted(_ app: String) -> Bool { muted.contains(app.lowercased()) }

    func toggleMute(_ app: String) {
        let key = app.lowercased()
        if muted.contains(key) { muted.remove(key) } else { muted.insert(key) }
        UserDefaults.standard.set(Array(muted), forKey: "mutedAlertApps")
        publish()
    }

    func dismiss(_ alert: Alert) {
        dismissed.insert(alert.id)
        UserDefaults.standard.set(Array(dismissed), forKey: "dismissedAlerts")
        publish()
    }

    func clearAll() {
        dismissed.formUnion(items.map(\.id))
        UserDefaults.standard.set(Array(dismissed), forKey: "dismissedAlerts")
        markRead()
        publish()
    }

    func markRead() {
        seenUntil = Date()
        UserDefaults.standard.set(seenUntil.timeIntervalSince1970, forKey: "alertsSeenUntil")
    }

    /// Goes where the notification points (the Messages conversation), otherwise opens the app.
    func open(_ alert: Alert) {
        if let link = alert.link, NSWorkspace.shared.open(link) { return }
        if let url = Self.appURL(alert.app) { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
    }

    /// System Settings › Notifications for that app, to set its alert style to None.
    static func openSystemSettings(for app: String) {
        let id = app.replacingOccurrences(of: "_system_center_:", with: "")
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") { NSWorkspace.shared.open(url) }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
    }

    func name(_ app: String) -> String {
        if let n = names[app] { return n }
        let n = Self.appURL(app).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? app.components(separatedBy: ".").last ?? app
        names[app] = n
        return n
    }

    func icon(_ app: String) -> NSImage {
        if let i = icons[app] { return i }
        let i = Self.appURL(app).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil) ?? NSImage()
        icons[app] = i
        return i
    }

    private static func appURL(_ app: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.replacingOccurrences(of: "_system_center_:", with: ""))
    }

    /// Every notification in the record, or nil if the database can't be read (no access yet).
    private static func read() -> [Alert]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(folder + "db", &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        defer { sqlite3_close(db) }
        var st: OpaquePointer?
        let sql = "SELECT r.uuid, a.identifier, r.data, r.delivered_date FROM record r JOIN app a ON a.app_id = r.app_id"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        var out: [Alert] = []
        while sqlite3_step(st) == SQLITE_ROW {
            guard let uuid = blob(st, 0), let blob = blob(st, 2),
                  let plist = try? PropertyListSerialization.propertyList(from: blob, format: nil) as? [String: Any],
                  let req = plist["req"] as? [String: Any] else { continue }
            let app = plist["app"] as? String ?? sqlite3_column_text(st, 1).map { String(cString: $0) } ?? ""
            let when = plist["date"] as? Double ?? sqlite3_column_double(st, 3)
            let title = req["titl"] as? String ?? "", body = req["body"] as? String ?? ""
            guard !(title.isEmpty && body.isEmpty) else { continue }
            out.append(Alert(id: uuid, app: app, title: title, subtitle: req["subt"] as? String ?? "", body: body,
                             date: Date(timeIntervalSinceReferenceDate: when), link: (req["durl"] as? String).flatMap(URL.init(string:))))
        }
        return out
    }

    private static func blob(_ st: OpaquePointer?, _ column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(st, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(st, column)))
    }
}
