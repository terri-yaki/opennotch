import SwiftUI

/// Now playing (artwork, title, progress, controls) on the left, synced lyrics on the right.
struct MusicView: View {
    @ObservedObject var music = MusicStore.shared
    @AppStorage(Theme.storageKey) private var theme: Theme = .purple

    var body: some View {
        if !music.hasTrack {
            VStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 26, weight: .light))
                Text("Nothing playing")
                    .font(.system(size: 13, weight: .medium))
                Text("Play something in Apple Music to see it here, with live lyrics.")
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .opacity(0.55)
            }
            .foregroundStyle(Color.white.opacity(0.8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 16) {
                nowPlaying.frame(width: 140)
                LyricsPanel(music: music, accent: theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let art = music.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(music.isPlaying ? 1 : 0.92)
            .animation(.spring(duration: 0.35), value: music.isPlaying)

            VStack(alignment: .leading, spacing: 1) {
                Text(music.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(music.artist).font(.system(size: 11)).opacity(0.6).lineLimit(1)
            }
            .foregroundStyle(.white)

            ProgressLine(music: music, accent: theme.accent)

            HStack(spacing: 14) {
                ControlButton(symbol: "backward.fill", size: 12) { music.previous() }
                ControlButton(symbol: music.isPlaying ? "pause.fill" : "play.fill", size: 16) { music.playPause() }
                ControlButton(symbol: "forward.fill", size: 12) { music.next() }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ProgressLine: View {
    @ObservedObject var music: MusicStore
    let accent: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let position = music.position(at: timeline.date)
            let fraction = music.duration > 0 ? position / music.duration : 0
            VStack(spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(accent).frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 3)
                HStack {
                    Text(Self.format(position))
                    Spacer()
                    Text("-" + Self.format(max(0, music.duration - position)))
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .magnetic(0.3)
    }
}

/// Synced lyrics scroll so the current line sits in the middle, highlighted.
private struct LyricsPanel: View {
    @ObservedObject var music: MusicStore
    let accent: Color

    var body: some View {
        switch music.lyrics {
        case .none, .loading:
            message("Looking up lyrics…")
        case .notFound:
            message("No lyrics found for this song")
        case .plain(let text):
            ScrollView(showsIndicators: false) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .synced(let lines):
            TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                // Lead slightly so the line lights up as it's sung, not after.
                let position = music.position(at: timeline.date) + 0.25
                let current = lines.lastIndex(where: { $0.time <= position }) ?? -1
                SyncedLyrics(lines: lines, current: current, accent: accent)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SyncedLyrics: View {
    let lines: [MusicStore.LyricLine]
    let current: Int
    let accent: Color

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    Color.clear.frame(height: 50)
                    ForEach(lines) { line in
                        let isCurrent = line.id == current
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: isCurrent ? 14 : 12, weight: isCurrent ? .bold : .medium))
                            .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(line.id < current ? 0.3 : 0.5))
                            .shadow(color: isCurrent ? accent.opacity(0.8) : .clear, radius: 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                    Color.clear.frame(height: 60)
                }
                .animation(.easeOut(duration: 0.25), value: current)
            }
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear],
                                 startPoint: .top, endPoint: .bottom))
            .onAppear { if current >= 0 { proxy.scrollTo(current, anchor: .center) } }
            .onChange(of: current) { _, new in
                guard new >= 0 else { return }
                withAnimation(.spring(duration: 0.45)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }
}
