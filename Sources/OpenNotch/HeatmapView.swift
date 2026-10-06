import SwiftUI

/// The Activity tab: full-height heatmap sections stacked vertically, one page per scroll.
/// OpenNotch activity (theme color), then Claude / Codex / Grok token usage (brand colors),
/// then a live per-core CPU heatmap with memory use.
struct HeatmapView: View {
    @ObservedObject var activity: ActivityStore
    @ObservedObject private var usage = UsageStore.shared
    @State private var page: Int? = 0

    private enum Section: Int, CaseIterable, Identifiable {
        case activity, claude, codex, grok, system
        var id: Int { rawValue }
        var tool: AITool? {
            switch self {
            case .claude: return .claude
            case .codex: return .codex
            case .grok: return .grok
            default: return nil
            }
        }
    }

    var body: some View {
        let height = NotchState.contentSize.height
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Section.allCases) { section in
                    Group {
                        switch section {
                        case .activity: ActivitySection(activity: activity)
                        case .system: SystemSection()
                        default: ToolSection(tool: section.tool!, usage: usage.usage[section.tool!])
                        }
                    }
                    .padding(.trailing, 14) // room for the page dots
                    .frame(height: height)
                    .id(section.rawValue)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .overlay(alignment: .trailing) { pageDots }
        .task {
            // Refresh usage while this tab is open; stops when it goes away.
            while !Task.isCancelled {
                usage.refreshIfStale()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onAppear { SystemMonitor.shared.start() }
        .onDisappear { SystemMonitor.shared.stop() }
    }

    private var pageDots: some View {
        VStack(spacing: 6) {
            ForEach(Section.allCases) { section in
                let selected = (page ?? 0) == section.rawValue
                Button {
                    withAnimation(.spring(duration: 0.4)) { page = section.rawValue }
                } label: {
                    Capsule()
                        .fill(Color.white.opacity(selected ? 0.9 : 0.25))
                        .frame(width: 4, height: selected ? 14 : 4)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .magnetic(0.3, maxShift: 3, range: 20)
            }
        }
        .animation(.spring(duration: 0.3), value: page)
    }
}

// MARK: - Sections

/// Files shelved and clips copied per day, in the theme color, with the theme picker.
struct ActivitySection: View {
    @ObservedObject var activity: ActivityStore
    @AppStorage(Theme.storageKey) private var theme: Theme = .purple

    var body: some View {
        SectionLayout {
            PromptLine(command: "opennotch --activity --weeks \(heatmapWeeks)", accent: theme.accent) {
                ThemePicker(selection: $theme)
            }
        } grid: {
            HeatmapGrid(grid: activity.grid(weeks: heatmapWeeks), level: activityLevel) { level, wave, col, cols, t in
                themeColor(level: level, wave: wave, hue: theme.hue(column: col, of: cols, time: t))
            }
        } footer: {
            HStack(spacing: 0) {
                Text("\(activity.total) contributions").foregroundStyle(Color.white.opacity(0.7))
                Text("  |  streak ").foregroundStyle(Color.white.opacity(0.35))
                Text("\(activity.streak)d").foregroundStyle(theme.accent)
                Spacer()
                Legend { level in
                    themeColor(level: level, wave: 0.3, hue: theme.hue(column: level, of: 5, time: 0))
                }
            }
        }
    }

    private func activityLevel(_ count: Int) -> Int {
        switch count {
        case 0: return 0
        case 1: return 1
        case 2...3: return 2
        case 4...6: return 3
        default: return 4
        }
    }
}

/// One AI tool's daily tokens, in its brand color.
struct ToolSection: View {
    let tool: AITool
    let usage: ToolUsage?

    var body: some View {
        SectionLayout {
            PromptLine(command: "\(tool.rawValue) --usage --weeks \(heatmapWeeks)", accent: tool.color) {
                if let last = usage?.lastActive, Date().timeIntervalSince(last) < 120 {
                    LiveBadge(color: tool.color)
                }
            }
        } grid: {
            if let usage, usage.found {
                let grid = dayGrid(weeks: heatmapWeeks) { usage.tokens(on: $0) }
                let thresholds = quartiles(of: grid)
                HeatmapGrid(grid: grid, level: { tokenLevel($0, thresholds) }) { level, wave, _, _, _ in
                    brandColor(tool.color, level: level, wave: wave)
                }
            } else {
                Text(usage == nil ? "reading logs…" : "no \(tool.name) logs on this Mac")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: gridSize.width + 22, height: gridSize.height)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    stat(usage?.today ?? 0, "today")
                    divider
                    stat(usage?.lastSevenDays ?? 0, "7d")
                    divider
                    stat(usage?.total ?? 0, "\(heatmapWeeks)w")
                    if let cached = usage?.cachedToday, cached > 0 {
                        Text("  +\(formatTokens(cached)) cached").foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    limits
                    Spacer()
                    Legend { brandColor(tool.color, level: $0, wave: 0.3) }
                }
            }
        }
    }

    private var divider: some View {
        Text("  |  ").foregroundStyle(.white.opacity(0.25))
    }

    private func stat(_ tokens: Int, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(formatTokens(tokens)).foregroundStyle(tool.color)
            Text(label).foregroundStyle(.white.opacity(0.45))
        }
    }

    @ViewBuilder
    private var limits: some View {
        if let block = usage?.block {
            HStack(spacing: 4) {
                Text("5h window").foregroundStyle(.white.opacity(0.45))
                Text(formatTokens(block.tokens)).foregroundStyle(.white.opacity(0.85))
                Text("resets \(formatCountdown(to: block.resetsAt))").foregroundStyle(.white.opacity(0.45))
            }
        }
        ForEach(usage?.limits ?? [], id: \.label) { limit in
            HStack(spacing: 4) {
                Text(limit.label).foregroundStyle(.white.opacity(0.45))
                MeterBar(fraction: limit.usedPercent / 100, color: tool.color).frame(width: 34)
                Text("\(Int(limit.usedPercent.rounded()))%").foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

/// Per-core CPU load scrolling right to left (one column per second) and memory in use.
struct SystemSection: View {
    @ObservedObject private var system = SystemMonitor.shared
    @AppStorage(Theme.storageKey) private var theme: Theme = .purple

    var body: some View {
        let length = SystemMonitor.historyLength
        // grid[column][row]: columns are seconds (oldest first), rows are cores.
        let grid: [[Int?]] = (0..<length).map { col in
            system.cores.map { history in
                let index = history.count - length + col
                return index >= 0 ? Int((history[index] * 100).rounded()) : 0 // not sampled yet: dim cell
            }
        }
        let gb = 1_073_741_824.0
        let memFraction = Double(system.memoryUsed) / Double(max(system.memoryTotal, 1))

        SectionLayout {
            PromptLine(command: "top --cpu --mem --cores \(system.cores.count)", accent: theme.accent) {
                LiveBadge(color: theme.accent)
            }
        } grid: {
            if system.cores.isEmpty {
                Color.clear.frame(width: gridSize.width + 22, height: gridSize.height)
            } else {
                HeatmapGrid(grid: grid, rows: system.cores.count,
                            labels: coreLabels(system.cores.count), level: loadLevel) { level, wave, _, _, _ in
                    themeColor(level: level, wave: wave, hue: theme.baseHue ?? 0.76)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("cpu").foregroundStyle(.white.opacity(0.45)).frame(width: 26, alignment: .leading)
                    MeterBar(fraction: system.cpu, color: theme.accent)
                    Text("\(Int((system.cpu * 100).rounded()))%")
                        .foregroundStyle(.white.opacity(0.85)).frame(width: 96, alignment: .trailing)
                }
                HStack(spacing: 6) {
                    Text("mem").foregroundStyle(.white.opacity(0.45)).frame(width: 26, alignment: .leading)
                    MeterBar(fraction: memFraction, color: theme.accent)
                    Text(String(format: "%.1f / %.0f GB  %d%%", Double(system.memoryUsed) / gb,
                                Double(system.memoryTotal) / gb, Int((memFraction * 100).rounded())))
                        .foregroundStyle(.white.opacity(0.85)).frame(width: 96, alignment: .trailing)
                }
            }
        }
    }

    private func coreLabels(_ count: Int) -> [String] {
        (0..<count).map { $0 == 0 ? "c0" : ($0 == count - 1 ? "c\($0)" : "") }
    }

    private func loadLevel(_ percent: Int) -> Int {
        switch percent {
        case ..<8: return 0
        case ..<30: return 1
        case ..<55: return 2
        case ..<80: return 3
        default: return 4
        }
    }
}

// MARK: - Building blocks

let heatmapWeeks = 36
private let cell: CGFloat = 8
private let gap: CGFloat = 2.5
private let gridSize = CGSize(width: CGFloat(heatmapWeeks) * (cell + gap) - gap, height: 7 * (cell + gap) - gap)

/// Prompt line on top, grid in the middle, footer below, centered in the page.
private struct SectionLayout<Prompt: View, Grid: View, Footer: View>: View {
    @ViewBuilder let prompt: Prompt
    @ViewBuilder let grid: Grid
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            prompt.font(.system(size: 10, design: .monospaced))
            grid
            footer.font(.system(size: 9, design: .monospaced))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct PromptLine<Trailing: View>: View {
    let command: String
    let accent: Color
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            Text("$ ").foregroundStyle(accent)
            Text(command).foregroundStyle(Color.white.opacity(0.8))
            Text("_").foregroundStyle(accent).opacity(0.9)
            Spacer()
            trailing
        }
    }
}

/// The animated grid. Every cell is one value; a sine wave of brightness (and, for theme
/// colors, hue) rolls diagonally across it so the whole thing ripples.
private struct HeatmapGrid: View {
    let grid: [[Int?]]                      // grid[column][row]
    var rows = 7
    var labels: [String]? = nil             // one per row; defaults to weekdays
    let level: (Int) -> Int                 // value -> 0...4
    let color: (_ level: Int, _ wave: Double, _ column: Int, _ columns: Int, _ time: Double) -> Color

    var body: some View {
        // Keep the overall height the same as a 7-row grid; many rows just get thinner.
        let rowPitch = (gridSize.height + gap) / CGFloat(rows)
        let cellHeight = rowPitch - (rows > 7 ? 1.5 : gap)
        let rowGap = rowPitch - cellHeight
        let rowLabels = labels ?? weekdayLabels.enumerated().map { [1, 3, 5].contains($0.offset) ? $0.element : "" }

        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .trailing, spacing: rowGap) {
                ForEach(0..<rows, id: \.self) { row in
                    Text(row < rowLabels.count ? rowLabels[row] : "")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .fixedSize()
                        .frame(height: cellHeight)
                }
            }
            .frame(width: 16, alignment: .trailing)

            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                Canvas { context, _ in
                    let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
                    for col in 0..<grid.count {
                        for row in 0..<min(rows, grid[col].count) {
                            guard let value = grid[col][row] else { continue }
                            let wave = sin(t * 1.7 + Double(col) * 0.30 + Double(row) * 0.22)
                            let rect = CGRect(x: CGFloat(col) * (cell + gap), y: CGFloat(row) * rowPitch,
                                              width: cell, height: cellHeight)
                            context.fill(Path(roundedRect: rect, cornerRadius: min(2, cellHeight / 3)),
                                         with: .color(color(level(value), wave, col, grid.count, t)))
                        }
                    }
                }
            }
            .frame(width: gridSize.width, height: gridSize.height)
        }
    }
}

private struct Legend: View {
    let color: (Int) -> Color

    var body: some View {
        HStack(spacing: 0) {
            Text("less ").foregroundStyle(Color.white.opacity(0.4))
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(level))
                    .frame(width: 8, height: 8)
                    .padding(.horizontal, 1)
            }
            Text(" more").foregroundStyle(Color.white.opacity(0.4))
        }
    }
}

private struct MeterBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(color).frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 4)
        .animation(.spring(duration: 0.5), value: fraction)
    }
}

/// Pulsing "live" tag.
private struct LiveBadge: View {
    let color: Color
    @State private var on = false

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5).opacity(on ? 1 : 0.3)
            Text("live").foregroundStyle(color.opacity(0.9))
        }
        .font(.system(size: 9, design: .monospaced))
        .animation(.easeInOut(duration: 0.8).repeatForever(), value: on)
        .onAppear { on = true }
    }
}

// MARK: - Helpers

/// Short weekday names rotated to start on the locale's first weekday, matching the rows of
/// `dayGrid` and `ActivityStore.grid`.
private let weekdayLabels: [String] = {
    let calendar = Calendar.current
    let symbols = calendar.shortWeekdaySymbols
    let start = calendar.firstWeekday - 1
    return Array(symbols[start...] + symbols[..<start])
}()

/// grid[column][row]: columns are weeks (oldest first), rows are weekdays; future days are nil.
private func dayGrid(weeks: Int, value: (Date) -> Int) -> [[Int?]] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
    guard let first = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: weekStart) else { return [] }
    return (0..<weeks).map { col in
        (0..<7).map { row in
            guard let date = calendar.date(byAdding: .day, value: col * 7 + row, to: first),
                  date <= today else { return nil }
            return value(date)
        }
    }
}

/// Quartiles of the non-zero days, so each tool's levels adapt to its own volume.
private func quartiles(of grid: [[Int?]]) -> [Int] {
    let values = grid.flatMap { $0 }.compactMap { $0 }.filter { $0 > 0 }.sorted()
    guard !values.isEmpty else { return [1, 1, 1] }
    return [values[values.count / 4], values[values.count / 2], values[values.count * 3 / 4]]
}

private func tokenLevel(_ tokens: Int, _ q: [Int]) -> Int {
    if tokens <= 0 { return 0 }
    if tokens <= q[0] { return 1 }
    if tokens <= q[1] { return 2 }
    if tokens <= q[2] { return 3 }
    return 4
}

/// Ramp of a hue by level; the wave nudges the hue and pulses brightness. Empty cells still
/// shimmer faintly so the grid feels alive.
private func themeColor(level: Int, wave: Double, hue base: Double) -> Color {
    let w = (wave + 1) / 2
    if level == 0 { return Color(white: 0.14 + 0.07 * w) }
    let hue = (base + 0.04 * wave + 1).truncatingRemainder(dividingBy: 1)
    let brightness = 0.30 + 0.15 * Double(level) + 0.12 * w
    return Color(hue: hue, saturation: 0.78, brightness: min(brightness, 1.0))
}

/// A fixed brand color ramped by opacity over the black dome.
private func brandColor(_ base: Color, level: Int, wave: Double) -> Color {
    let w = (wave + 1) / 2
    if level == 0 { return Color(white: 0.14 + 0.07 * w) }
    return base.opacity(min(1, 0.22 + 0.19 * Double(level) + 0.1 * w))
}

func formatTokens(_ n: Int) -> String {
    switch n {
    case 1_000_000_000...: return String(format: "%.1fB", Double(n) / 1e9)
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1e6)
    case 1_000...: return String(format: "%.1fK", Double(n) / 1e3)
    default: return "\(n)"
    }
}

private func formatCountdown(to date: Date) -> String {
    let s = max(0, Int(date.timeIntervalSinceNow))
    return s >= 3600 ? "\(s / 3600)h\((s % 3600) / 60)m" : "\(s / 60)m"
}
