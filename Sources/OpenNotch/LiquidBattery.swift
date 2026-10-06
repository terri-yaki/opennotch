import SwiftUI

/// A battery icon filled with sloshing liquid. Vertical batteries fill from the bottom with
/// a wavy surface; horizontal ones fill from the left with a wavy front.
/// `fill` animates the liquid in: 0 is empty, 1 is the real level.
struct LiquidBattery: View {
    let level: Double
    let charging: Bool
    var vertical = false
    var fill: Double = 1

    private var color: Color {
        if charging { return Color(red: 0.25, green: 0.88, blue: 0.45) }
        if level <= 0.2 { return Color(red: 1, green: 0.32, blue: 0.3) }
        return .white
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000)
            Canvas { ctx, size in
                draw(in: &ctx, size: size, t: t)
            }
        }
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let nub: CGFloat = vertical ? size.height * 0.1 : size.width * 0.08
        let body = vertical
            ? CGRect(x: 0, y: nub, width: size.width, height: size.height - nub)
            : CGRect(x: 0, y: 0, width: size.width - nub, height: size.height)
        let corner = min(body.width, body.height) * 0.28
        let line: CGFloat = 1.2

        // Shell and terminal nub.
        ctx.stroke(Path(roundedRect: body.insetBy(dx: line / 2, dy: line / 2), cornerRadius: corner),
                   with: .color(.white.opacity(0.55)), lineWidth: line)
        let nubRect = vertical
            ? CGRect(x: size.width * 0.3, y: 0, width: size.width * 0.4, height: nub)
            : CGRect(x: body.maxX, y: size.height * 0.3, width: nub, height: size.height * 0.4)
        ctx.fill(Path(roundedRect: nubRect, cornerRadius: nub * 0.4), with: .color(.white.opacity(0.55)))

        // Liquid, clipped to the inside of the shell.
        let inner = body.insetBy(dx: line + 1, dy: line + 1)
        let amount = CGFloat(max(0, min(1, level * fill)))
        var liquid = ctx
        liquid.clip(to: Path(roundedRect: inner, cornerRadius: max(0, corner - line - 1)))

        let wave = Path { p in
            let amp = min(inner.width, inner.height) * 0.08
            let steps = 24
            if vertical {
                let surface = inner.maxY - inner.height * amount
                p.move(to: CGPoint(x: inner.minX, y: inner.maxY))
                for i in 0...steps {
                    let x = inner.minX + inner.width * CGFloat(i) / CGFloat(steps)
                    let y = surface + amp * CGFloat(sin(Double(i) / Double(steps) * 2 * .pi + t * 5))
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                p.addLine(to: CGPoint(x: inner.maxX, y: inner.maxY))
            } else {
                let front = inner.minX + inner.width * amount
                p.move(to: CGPoint(x: inner.minX, y: inner.minY))
                for i in 0...steps {
                    let y = inner.minY + inner.height * CGFloat(i) / CGFloat(steps)
                    let x = front + amp * CGFloat(sin(Double(i) / Double(steps) * 2 * .pi + t * 5))
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                p.addLine(to: CGPoint(x: inner.minX, y: inner.maxY))
            }
            p.closeSubpath()
        }
        liquid.fill(wave, with: .linearGradient(
            Gradient(colors: [color.opacity(0.75), color]),
            startPoint: CGPoint(x: inner.midX, y: inner.minY), endPoint: CGPoint(x: inner.midX, y: inner.maxY)))

        if charging {
            let bolt = Text(Image(systemName: "bolt.fill"))
                .font(.system(size: min(inner.width, inner.height) * (vertical ? 0.7 : 0.9), weight: .bold))
                .foregroundColor(.white)
            ctx.draw(bolt, at: CGPoint(x: inner.midX, y: inner.midY))
        }
    }
}
