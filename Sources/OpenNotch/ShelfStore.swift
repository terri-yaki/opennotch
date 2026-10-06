import AppKit

struct ShelfItem: Identifiable {
    let id = UUID()
    let url: URL
    let icon: NSImage

    var name: String { url.lastPathComponent }

    init(url: URL) {
        self.url = url
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Files parked on the shelf. Only references (paths) are stored; nothing is copied.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    private let key = "OpenNotch.shelfPaths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { ShelfItem(url: $0) }
    }

    func add(_ urls: [URL]) {
        var added = 0
        for url in urls where url.isFileURL {
            let standardized = url.standardizedFileURL
            if items.contains(where: { $0.url == standardized }) { continue }
            items.insert(ShelfItem(url: standardized), at: 0)
            added += 1
        }
        if added > 0 {
            save()
            ActivityStore.shared.record(added)
        }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    /// Drop entries whose files were moved or deleted.
    func prune() {
        let before = items.count
        items.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
        if items.count != before { save() }
    }

    private func save() {
        UserDefaults.standard.set(items.map { $0.url.path }, forKey: key)
    }
}
