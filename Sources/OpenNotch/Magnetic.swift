import SwiftUI

/// Name of the coordinate space the root view declares; cursor positions use it too.
let notchSpace = "notch"

/// Cursor position in the panel's coordinate space (top-left origin), or nil while the
/// panel is collapsed. Fed by NotchController's mouse monitors, which see every move
/// even though the panel never becomes key.
@MainActor
final class CursorTracker: ObservableObject {
    @Published var location: CGPoint?
}

/// Pulls a view a few points toward the cursor when it comes near, springing back as it
/// leaves, so the controls feel magnetic.
private struct Magnetic: ViewModifier {
    @EnvironmentObject private var cursor: CursorTracker
    let strength: CGFloat
    let maxShift: CGFloat
    let range: CGFloat
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        let (shift, closeness) = pull()
        content
            .scaleEffect(1 + 0.05 * closeness)
            .offset(shift)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: shift)
            // Measured after .offset, so this reads the resting frame and doesn't feed back.
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { frame = geo.frame(in: .named(notchSpace)) }
                    .onChange(of: geo.frame(in: .named(notchSpace))) { _, new in frame = new }
            })
    }

    private func pull() -> (CGSize, CGFloat) {
        guard let p = cursor.location, frame != .zero else { return (.zero, 0) }
        let dx = p.x - frame.midX
        let dy = p.y - frame.midY
        let reach = range + max(frame.width, frame.height) / 2
        let dist = hypot(dx, dy)
        guard dist < reach else { return (.zero, 0) }
        let closeness = 1 - dist / reach
        let clamp = { (v: CGFloat) in max(-maxShift, min(maxShift, v)) }
        return (CGSize(width: clamp(dx * strength * closeness),
                       height: clamp(dy * strength * closeness)),
                closeness)
    }
}

extension View {
    func magnetic(_ strength: CGFloat = 0.25, maxShift: CGFloat = 5, range: CGFloat = 50) -> some View {
        modifier(Magnetic(strength: strength, maxShift: maxShift, range: range))
    }
}
