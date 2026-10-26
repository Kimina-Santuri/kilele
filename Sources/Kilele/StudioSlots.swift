import AppKit

/// "Open next at Santuri": each studio room's next free hour, from the bookings site's public next_open_times()
/// (the same list the bookings.santuri.org hero shows). Uses the site's publishable key, which is public by design.
final class StudioSlots: ObservableObject {
    struct Slot: Identifiable, Equatable {
        let id: String   // room slug
        let name: String
        let start: Date
    }

    @Published private(set) var slots: [Slot] = []
    @Published private(set) var failed = false

    private static let endpoint = URL(string: "https://gudbkpwxszdtirewawep.supabase.co/rest/v1/rpc/next_open_times")!
    private static let publishableKey = "sb_publishable_dWNhwRs1aG85mkm6CUK2QQ_I66lX3Rx"
    private var lastLoad = Date.distantPast

    /// At most once a minute; times move on as people book.
    func reload() {
        guard Date().timeIntervalSince(lastLoad) > 60 else { return }
        lastLoad = Date()
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue(Self.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let rows = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [[String: Any]]) ?? []
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let slots: [Slot] = rows.compactMap { row in
                guard let slug = row["slug"] as? String, let name = row["name"] as? String,
                      let when = row["starts_at"] as? String, let start = Self.date(when) else { return nil }
                return Slot(id: slug, name: name, start: start)
            }
            DispatchQueue.main.async { self?.slots = slots; self?.failed = !ok }
        }.resume()
    }

    func book(_ slot: Slot) {
        NSWorkspace.shared.open(URL(string: "https://bookings.santuri.org/book.html?space=\(slot.id)")!)
    }

    private static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
