import SwiftUI

struct NotchRootView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject private var music = MusicStore.shared
    @ObservedObject private var battery = BatteryMonitor.shared

    private var shape: NotchShape {
        NotchShape(progress: state.expanded ? 1 : 0, tab: state.collapsedSize)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(Color.black)

            if state.expanded {
                expandedContent
                    .frame(width: NotchState.expandedSize.width,
                           height: NotchState.expandedSize.height,
                           alignment: .top)
                    .transition(.opacity)
            } else if state.showPet || state.batteryToast {
                collapsedContent
                    .transition(.opacity)
            }

            if state.dropTargeted {
                shape.stroke(Color.accentColor.opacity(0.9), lineWidth: 4) // half of it is clipped away
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(shape)
        .coordinateSpace(name: notchSpace)
        .environmentObject(state.cursor)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .animation(.spring(duration: 0.42, bounce: 0), value: state.expanded)
        .animation(.spring(duration: 0.3), value: state.showPet)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            shelf.add(files)
            state.tab = .shelf
            state.pet.feed()
            return true
        } isTargeted: { targeted in
            state.dropTargeted = targeted
        }
        .onChange(of: battery.plugInCount) { _, _ in showBatteryToast() }
    }

    @State private var toastTask: Task<Void, Never>?

    private func showBatteryToast() {
        state.pet.feed()
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.4)) { state.batteryToast = true }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.4)) { state.batteryToast = false }
        }
    }

    // MARK: Collapsed layout

    /// Left wing: battery (just after plugging in), else album art (while music plays), else
    /// the shelf count. Middle: the hardware notch. Right wing: the pet.
    private var collapsedContent: some View {
        HStack(spacing: 0) {
            Group {
                if state.batteryToast {
                    BatteryToast(level: battery.level, charging: battery.isCharging || battery.isPluggedIn)
                        .transition(.scale.combined(with: .opacity))
                } else if music.isPlaying {
                    Group {
                        if let art = music.artwork {
                            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "music.note").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .transition(.opacity)
                } else if !shelf.items.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "tray.fill").font(.system(size: 8))
                        Text("\(shelf.items.count)").font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .frame(width: state.wingWidth)

            Color.clear.frame(width: state.notchSize.width)

            Group {
                if state.showPet { PetView(pet: state.pet) } else { Color.clear }
            }
            .frame(width: state.wingWidth)
        }
        .frame(height: state.collapsedSize.height)
    }

    // MARK: Expanded layout

    private var headerHeight: CGFloat {
        state.hasNotch ? state.notchSize.height : 32
    }

    private var expandedContent: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                    .frame(height: headerHeight)
                    .padding(.horizontal, 44)

                Group {
                    switch state.tab {
                    case .shelf: ShelfView(shelf: shelf)
                    case .clipboard: ClipboardView(clipboard: clipboard)
                    case .music: MusicView()
                    case .activity: HeatmapView(activity: ActivityStore.shared)
                    }
                }
                .frame(width: NotchState.contentSize.width, height: NotchState.contentSize.height)
                .padding(.top, 8)
            }

            if state.showPet {
                let spot = NotchState.domePetRect
                PetView(pet: state.pet)
                    .frame(width: spot.width, height: spot.height)
                    .position(x: spot.midX, y: spot.midY)
            }
        }
    }

    /// Tabs sit left of the notch, controls right of it, so nothing hides behind the hardware.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(NotchState.Tab.allCases) { tab in
                    TabButton(tab: tab, selected: state.tab == tab) { state.tab = tab }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if state.hasNotch {
                Color.clear.frame(width: state.notchSize.width)
            }

            HStack(spacing: 8) {
                if battery.hasBattery {
                    LiquidBattery(level: battery.level, charging: battery.isCharging)
                        .frame(width: 22, height: 11)
                        .help("Battery \(Int((battery.level * 100).rounded()))%")
                        .magnetic(0.2, maxShift: 3)
                }
                if state.tab == .shelf, !shelf.items.isEmpty {
                    IconButton(symbol: "trash", help: "Clear shelf") { shelf.clear() }
                }
                if state.tab == .clipboard, !clipboard.entries.isEmpty {
                    IconButton(symbol: "trash", help: "Clear unpinned clips") { clipboard.clearUnpinned() }
                }
                IconButton(symbol: state.pinned ? "pin.fill" : "pin",
                           help: state.pinned ? "Unpin" : "Keep open") {
                    state.pinned.toggle()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Shape

/// The notch tab itself, grown outward: its sides move out, its bottom moves down and its
/// bottom corners round off, all from one progress value. Progress 0 is exactly the tab
/// (notch plus wings, 10pt corners); progress 1 is exactly a semicircle filling the panel.
/// The corner radius runs ahead of the size, so the shape never looks boxy on the way.
struct NotchShape: Shape {
    var progress: CGFloat
    var tab: CGSize

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(progress, AnimatablePair(tab.width, tab.height)) }
        set {
            progress = newValue.first
            tab = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(max(progress, 0), 1) // a spring overshoot would push past the window edges
        let finalDepth = min(rect.height, rect.width / 2)

        let width = tab.width + (rect.width - tab.width) * t
        let depth = tab.height + (finalDepth - tab.height) * t
        let ease = 1 - (1 - t) * (1 - t)
        let radius = min(10 + (finalDepth - 10) * ease, depth, width / 2)

        let frame = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: depth)
        return UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius,
                                      style: .circular)
            .path(in: frame)
    }
}

// MARK: - Battery toast

/// Vertical battery that fills with liquid from empty up to the current level, plus the %.
private struct BatteryToast: View {
    let level: Double
    let charging: Bool
    @State private var fill: Double = 0

    var body: some View {
        HStack(spacing: 4) {
            LiquidBattery(level: level, charging: charging, vertical: true, fill: fill)
                .frame(width: 12, height: 20)
            Text("\(Int((level * fill * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .onAppear { withAnimation(.easeOut(duration: 1.4)) { fill = 1 } }
    }
}

// MARK: - Small controls

private struct TabButton: View {
    let tab: NotchState.Tab
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.45))
                .frame(width: 30, height: 22)
                .background(selected ? Color.white.opacity(0.16) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .magnetic(0.3)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.65))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .magnetic(0.3)
    }
}
