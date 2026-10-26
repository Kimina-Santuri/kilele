import EventKit

/// The next few events (today and tomorrow) and reminders due by the end of today.
/// Access is first asked for the first time the notch opens, not at launch.
final class Agenda: ObservableObject {
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var reminders: [EKReminder] = []
    @Published private(set) var calendarAllowed = true
    /// Timed events from now to the end of tomorrow (for the session timer and countdown).
    @Published private(set) var upcoming: [EKEvent] = []
    /// The event the countdown follows (a gig, a deadline); nil = the next event.
    @Published private(set) var pinned: EKEvent?
    /// Called with an event's title 10 minutes before it ends (the session timer's nudge).
    var onEndingSoon: (String) -> Void = { _ in }
    private var nudged: Set<String> = []
    private var ticker: Timer?

    private let store = EKEventStore()
    private var started = false

    /// At launch: start right away only if access was already given, so the pill can show the next event without a prompt.
    func startIfAllowed() {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { start() }
    }

    func start() {
        guard !started else { reload(); return }
        started = true
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async { self?.calendarAllowed = granted; self?.reload() }
        }
        store.requestFullAccessToReminders { [weak self] _, _ in
            DispatchQueue.main.async { self?.reload() }
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in self?.reload() }
        ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.checkEnding() }
    }

    /// The timed event happening now, if any (the studio session, a class, a call).
    func session(at date: Date = Date()) -> EKEvent? {
        upcoming.first { $0.startDate <= date && $0.endDate > date }
    }

    /// What the countdown points at: the pinned event while it's still ahead, otherwise the next timed event.
    func countdownTarget(at date: Date = Date()) -> EKEvent? {
        if let pinned, pinned.startDate > date { return pinned }
        return upcoming.first { $0.startDate > date }
    }

    func pin(_ event: EKEvent?) {
        pinned = event
        UserDefaults.standard.set(event?.eventIdentifier, forKey: "pinnedEvent")
    }

    private func checkEnding() {
        guard let now = session() else { return }
        let left = now.endDate.timeIntervalSinceNow
        let key = "\(now.eventIdentifier ?? "")|\(now.endDate.timeIntervalSince1970)"
        if left <= 600 && left > 0 && !nudged.contains(key) {
            nudged.insert(key)
            onEndingSoon(now.title ?? "Session")
        }
    }

    /// "25m", "3h 20m", "2d 4h".
    static func span(_ seconds: TimeInterval) -> String {
        let m = max(0, Int(seconds / 60))
        if m < 60 { return "\(m)m" }
        if m < 1440 { return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m" }
        return "\(m / 1440)d \(m % 1440 / 60)h"
    }

    func reload() {
        let calendar = Calendar.current, now = Date(), today = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today)!
        let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: today)!

        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            // Start a day back so an event already under way still shows until it ends.
            let match = store.predicateForEvents(withStart: today.addingTimeInterval(-86400), end: endOfTomorrow, calendars: nil)
            let all = store.events(matching: match).filter { $0.endDate > now }.sorted { $0.startDate < $1.startDate }
            events = Array(all.filter { !$0.isAllDay || calendar.isDateInToday($0.startDate) }.prefix(4))
            upcoming = all.filter { !$0.isAllDay }
            if let id = UserDefaults.standard.string(forKey: "pinnedEvent") {
                pinned = store.event(withIdentifier: id).flatMap { $0.endDate > now ? $0 : nil }
            }
            checkEnding()
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            let match = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday, calendars: nil)
            store.fetchReminders(matching: match) { [weak self] found in
                DispatchQueue.main.async { self?.reminders = Array((found ?? []).prefix(4)) }
            }
        }
    }

    func complete(_ reminder: EKReminder) {
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
        reload()
    }
}
