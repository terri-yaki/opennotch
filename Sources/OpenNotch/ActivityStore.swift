import Foundation

/// Per-day counts of things you did with OpenNotch (files shelved, clips copied).
/// Feeds the heatmap tab. Stored locally in UserDefaults as "yyyy-MM-dd" -> count.
@MainActor
final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()

    @Published private(set) var counts: [String: Int]

    private let key = "OpenNotch.activity"
    private let calendar = Calendar.current
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {
        counts = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    func record(_ n: Int = 1) {
        counts[formatter.string(from: Date()), default: 0] += n
        UserDefaults.standard.set(counts, forKey: key)
    }

    func count(on date: Date) -> Int {
        counts[formatter.string(from: date)] ?? 0
    }

    func clear() {
        counts = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }

    var total: Int { counts.values.reduce(0, +) }

    /// Consecutive days with activity, ending today (or yesterday if today is still empty).
    var streak: Int {
        var day = Date()
        if count(on: day) == 0 {
            guard let y = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = y
        }
        var streak = 0
        while count(on: day) > 0 {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// Grid of per-day counts: `grid[column][row]`, columns are weeks (oldest first),
    /// rows are weekdays. Future days are nil.
    func grid(weeks: Int) -> [[Int?]] {
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        guard let first = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: weekStart) else { return [] }

        return (0..<weeks).map { col in
            (0..<7).map { row in
                guard let date = calendar.date(byAdding: .day, value: col * 7 + row, to: first),
                      date <= today else { return nil }
                return count(on: date)
            }
        }
    }
}
