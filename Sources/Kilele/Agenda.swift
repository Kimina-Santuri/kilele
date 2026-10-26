import EventKit

/// The next few events (today and tomorrow) and reminders due by the end of today.
/// Access is first asked for the first time the notch opens, not at launch.
final class Agenda: ObservableObject {
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var reminders: [EKReminder] = []
    @Published private(set) var calendarAllowed = true

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
    }

    func reload() {
        let calendar = Calendar.current, now = Date(), today = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today)!
        let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: today)!

        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            // Start a day back so an event already under way still shows until it ends.
            let match = store.predicateForEvents(withStart: today.addingTimeInterval(-86400), end: endOfTomorrow, calendars: nil)
            events = Array(store.events(matching: match)
                .filter { $0.endDate > now && (!$0.isAllDay || calendar.isDateInToday($0.startDate)) }
                .sorted { $0.startDate < $1.startDate }
                .prefix(4))
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
