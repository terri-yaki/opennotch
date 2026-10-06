import SwiftUI

/// The AI coding tools whose local logs OpenNotch reads, each with its fixed brand color.
enum AITool: String, CaseIterable, Identifiable {
    case claude, codex, grok
    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .grok: return "Grok"
        }
    }

    var color: Color {
        switch self {
        case .claude: return Color(red: 0.851, green: 0.467, blue: 0.341) // #D97757
        case .codex: return Color(red: 0.231, green: 0.51, blue: 0.965)   // #3B82F6
        case .grok: return Color(white: 0.9)                              // brand black, lifted for the dark notch
        }
    }
}

struct ToolUsage {
    struct Limit {
        let label: String
        let usedPercent: Double
        let resetsAt: Date?
    }

    /// Tokens per day (keyed by start of day). Tokens = uncached input + output (+ cache
    /// writes); cache reads are tracked separately in `cachedToday`.
    var days: [Date: Int] = [:]
    var cachedToday = 0
    var lastActive: Date?
    /// Claude's current 5-hour block (tokens so far, when it resets).
    var block: (tokens: Int, resetsAt: Date)?
    /// Codex's own rate-limit readings, when its logs include them.
    var limits: [Limit] = []
    var found = false

    func tokens(on date: Date, calendar: Calendar = .current) -> Int {
        days[calendar.startOfDay(for: date)] ?? 0
    }

    var today: Int { tokens(on: Date()) }

    var lastSevenDays: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reduce(0) { sum, back in
            sum + (calendar.date(byAdding: .day, value: -back, to: today).map { days[$0] ?? 0 } ?? 0)
        }
    }

    var total: Int { days.values.reduce(0, +) }
}

/// Reads token usage from the CLIs' local logs. Nothing leaves the Mac.
/// - Claude Code: ~/.claude/projects/**/*.jsonl (per-message `usage`)
/// - Codex: ~/.codex/sessions/**/*.jsonl (`token_count` events, incl. rate limits)
/// - Grok: ~/.grok/sessions/*/*/usage.json (per-turn counts)
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()
    nonisolated static let weeks = heatmapWeeks

    @Published private(set) var usage: [AITool: ToolUsage] = [:]
    @Published private(set) var updatedAt: Date?
    private var loading = false
    private let scanner = UsageScanner()

    private init() {}

    func refreshIfStale(maxAge: TimeInterval = 30) {
        guard !loading, (updatedAt.map { Date().timeIntervalSince($0) > maxAge } ?? true) else { return }
        loading = true
        let scanner = self.scanner
        Task.detached(priority: .utility) {
            let result = scanner.scan(now: Date(), weeks: Self.weeks)
            await MainActor.run {
                self.usage = result
                self.updatedAt = Date()
                self.loading = false
            }
        }
    }
}

/// Parses log files, caching each file's contribution by modification date so a refresh
/// only re-reads files that changed. Only ever used by one scan at a time.
private final class UsageScanner: @unchecked Sendable {
    /// What one file contributed.
    private struct FileResult {
        var days: [Date: Int] = [:]
        var cached: [Date: Int] = [:]
        var lastActive: Date?
        var recent: [(Date, Int)] = []          // last 24h, for Claude's 5-hour blocks
        var limits: (Date, [String: Any])?      // Codex's newest rate-limit reading
    }

    private let calendar = Calendar.current
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var cache: [URL: (Date, FileResult)] = [:]

    func scan(now: Date, weeks: Int) -> [AITool: ToolUsage] {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: weekStart) ?? weekStart
        let recentCutoff = now.addingTimeInterval(-24 * 3600)

        var result: [AITool: ToolUsage] = [:]
        var live = Set<URL>()
        for tool in AITool.allCases {
            var usage = ToolUsage()
            var recent: [(Date, Int)] = []
            var limits: (Date, [String: Any])?

            for (file, modified) in files(for: tool, since: cutoff) {
                usage.found = true
                live.insert(file)
                let part: FileResult
                if let hit = cache[file], hit.0 == modified {
                    part = hit.1
                } else {
                    part = parse(file, tool: tool, cutoff: cutoff, recentCutoff: recentCutoff)
                    cache[file] = (modified, part)
                }
                usage.days.merge(part.days, uniquingKeysWith: +)
                usage.cachedToday += part.cached[calendar.startOfDay(for: now)] ?? 0
                if let d = part.lastActive, usage.lastActive.map({ d > $0 }) ?? true { usage.lastActive = d }
                recent += part.recent.filter { $0.0 >= recentCutoff }
                if let l = part.limits, limits.map({ l.0 > $0.0 }) ?? true { limits = l }
            }

            if tool == .claude { usage.block = claudeBlock(recent, now: now) }
            if let limits { usage.limits = codexLimits(limits.1, now: now) }
            result[tool] = usage
        }
        cache = cache.filter { live.contains($0.key) }
        return result
    }

    // MARK: Files

    private func files(for tool: AITool, since cutoff: Date) -> [(URL, Date)] {
        let relative: String, ext: String
        switch tool {
        case .claude: (relative, ext) = (".claude/projects", "jsonl")
        case .codex: (relative, ext) = (".codex/sessions", "jsonl")
        case .grok: (relative, ext) = (".grok/sessions", "json")
        }
        let root = home.appendingPathComponent(relative)
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else { return [] }

        var result: [(URL, Date)] = []
        for case let url as URL in walker where url.pathExtension == ext {
            if tool == .grok, url.lastPathComponent != "usage.json" { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let modified = values?.contentModificationDate,
                  modified >= cutoff else { continue }
            result.append((url, modified))
        }
        return result
    }

    private func parse(_ file: URL, tool: AITool, cutoff: Date, recentCutoff: Date) -> FileResult {
        var r = FileResult()
        func add(_ tokens: Int, cached: Int, at date: Date) {
            guard date >= cutoff else { return }
            let day = calendar.startOfDay(for: date)
            r.days[day, default: 0] += tokens
            r.cached[day, default: 0] += cached
            if r.lastActive.map({ date > $0 }) ?? true { r.lastActive = date }
            if date >= recentCutoff { r.recent.append((date, tokens)) }
        }

        switch tool {
        case .claude:
            var seen = Set<String>()
            forEachLine(of: file, containing: "\"usage\"") { obj in
                guard obj["type"] as? String == "assistant",
                      let message = obj["message"] as? [String: Any],
                      let u = message["usage"] as? [String: Any],
                      let date = parseDate(obj["timestamp"]) else { return }
                // Streaming writes the same message more than once.
                let key = "\(message["id"] as? String ?? "")|\(obj["requestId"] as? String ?? "")"
                if key != "|" { guard seen.insert(key).inserted else { return } }
                add(int(u["input_tokens"]) + int(u["output_tokens"]) + int(u["cache_creation_input_tokens"]),
                    cached: int(u["cache_read_input_tokens"]), at: date)
            }

        case .codex:
            var lastTotal = -1
            forEachLine(of: file, containing: "\"token_count\"") { obj in
                guard let payload = obj["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let date = parseDate(obj["timestamp"]) else { return }
                if let limits = payload["rate_limits"] as? [String: Any], limits["primary"] is [String: Any],
                   r.limits.map({ date > $0.0 }) ?? true {
                    r.limits = (date, limits)
                }
                guard let info = payload["info"] as? [String: Any],
                      let turn = info["last_token_usage"] as? [String: Any] else { return }
                // Codex can repeat a token_count event; skip if the running total didn't move.
                let total = int((info["total_token_usage"] as? [String: Any])?["total_tokens"])
                guard total != lastTotal else { return }
                lastTotal = total
                let cached = int(turn["cached_input_tokens"])
                add(max(0, int(turn["input_tokens"]) - cached) + int(turn["output_tokens"]), cached: cached, at: date)
            }

        case .grok:
            guard let data = try? Data(contentsOf: file),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let turns = obj["turns"] as? [[String: Any]] else { break }
            for turn in turns {
                guard let date = parseDate(turn["endedAt"]) else { continue }
                add(int(turn["inputTokens"]) + int(turn["outputTokens"]) + int(turn["cacheCreationTokens"]),
                    cached: int(turn["cachedReadTokens"]), at: date)
            }
        }
        return r
    }

    // MARK: Limits

    /// 5-hour blocks: a block starts at the hour of the first message after the previous
    /// block expired (or after a 5-hour gap) and lasts five hours.
    private func claudeBlock(_ entries: [(Date, Int)], now: Date) -> (tokens: Int, resetsAt: Date)? {
        let window: TimeInterval = 5 * 3600
        var start: Date?, last: Date?, tokens = 0
        for (date, n) in entries.sorted(by: { $0.0 < $1.0 }) {
            if start == nil || date >= start! + window || date.timeIntervalSince(last!) >= window {
                start = calendar.dateInterval(of: .hour, for: date)?.start ?? date
                tokens = 0
            }
            tokens += n
            last = date
        }
        guard let start, start + window > now else { return nil }
        return (tokens, start + window)
    }

    private func codexLimits(_ limits: [String: Any], now: Date) -> [ToolUsage.Limit] {
        [("primary", "5h"), ("secondary", "week")].compactMap { key, fallback in
            guard let w = limits[key] as? [String: Any], let used = w["used_percent"] as? Double else { return nil }
            let reset = (w["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            let rolledOver = reset.map { $0 < now } ?? false // window reset since the last reading
            var label = fallback
            if let m = w["window_minutes"] as? Int {
                label = m == 10080 ? "week" : (m % 60 == 0 ? "\(m / 60)h" : "\(m)m")
            }
            return .init(label: label, usedPercent: rolledOver ? 0 : used, resetsAt: rolledOver ? nil : reset)
        }
    }

    // MARK: Helpers

    /// Calls `body` with each JSON line that contains `needle` (cheap prefilter before parsing).
    private func forEachLine(of url: URL, containing needle: String, _ body: ([String: Any]) -> Void) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") where line.contains(needle) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            body(obj)
        }
    }

    private func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }

    private let iso = ISO8601DateFormatter()

    /// ISO 8601 with any number of fractional digits ("…:34.492Z", "…:48.287756+00:00").
    private func parseDate(_ value: Any?) -> Date? {
        guard var s = value as? String else { return nil }
        if let dot = s.firstIndex(of: ".") {
            let end = s[dot...].dropFirst().firstIndex(where: { !$0.isNumber }) ?? s.endIndex
            s.removeSubrange(dot..<end)
        }
        return iso.date(from: s)
    }
}
