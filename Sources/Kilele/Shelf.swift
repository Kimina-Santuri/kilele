import AppKit

/// Files parked on the notch. Kept as bookmarks, so they survive restarts and follow a file if it's moved.
final class Shelf: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        var url: URL
    }

    @Published private(set) var items: [Item] = []
    @Published var hovered: UUID?
    private let key = "shelfBookmarks"

    init() {
        let saved = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        items = saved.compactMap { data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return Item(url: url)
        }
        save()
    }

    func accept(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async { self?.add(url) }
            }
        }
    }

    func add(_ url: URL) {
        guard !items.contains(where: { $0.url == url }) else { return }
        items.append(Item(url: url))
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        UserDefaults.standard.set(items.compactMap { try? $0.url.bookmarkData() }, forKey: key)
    }
}
