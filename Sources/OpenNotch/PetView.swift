import SwiftUI

/// The liquid pet: a gooey rainbow blob (metaballs via blur + alpha threshold) with eyes
/// that follow the cursor. Scales to whatever frame it's given; designed at 40×32.
struct PetView: View {
    let pet: PetModel
    @AppStorage(Theme.storageKey) private var theme: Theme = .purple

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            let _ = pet.dancing = MusicStore.shared.isPlaying
            let pose = pet.step(at: timeline.date)
            let baseHue = theme.baseHue
            Canvas { context, size in
                PetRenderer.draw(pose, baseHue: baseHue, in: &context, size: size)
            }
        }
        .allowsHitTesting(false)
    }
}

private enum PetRenderer {
    /// `baseHue` nil means rainbow; otherwise the liquid shimmers in shades around that hue.
    static func draw(_ p: PetPose, baseHue: Double?, in ctx: inout GraphicsContext, size: CGSize) {
        let k = min(size.width / 40, size.height / 32)
        let r = 9.5 * k
        let c = CGPoint(x: size.width / 2 + p.lean * 3 * k,
                        y: size.height / 2 + 2 * k - p.hop * k)

        let breathe = CGFloat(sin(p.time * (p.asleep ? 1.3 : 2.6)))
        let squash = CGFloat(sin(p.phase * 1.3)) * 0.08 * p.energy + breathe * 0.035 - p.hop * 0.02
        let sx = 1 + squash, sy = 1 - squash
        let saturation = p.asleep ? 0.45 : 0.8

        func hue(_ offset: Double) -> Color {
            guard let baseHue else {
                let h = (p.hue + offset).truncatingRemainder(dividingBy: 1)
                return Color(hue: h < 0 ? h + 1 : h, saturation: saturation, brightness: 1)
            }
            // Periodic in offset, so the conic gradient wraps around seamlessly.
            let angle = 2 * Double.pi * (offset + p.hue.truncatingRemainder(dividingBy: 1))
            let h = (baseHue + 0.07 * sin(angle) + 1).truncatingRemainder(dividingBy: 1)
            return Color(hue: h, saturation: saturation, brightness: 0.85 + 0.15 * cos(angle))
        }

        // Soft colored glow behind the body.
        var glow = ctx
        glow.addFilter(.blur(radius: 5 * k))
        glow.opacity = p.asleep ? 0.25 : 0.45 + 0.3 * Double(p.energy)
        glow.fill(ellipse(c, r * 1.1 * sx, r * sy), with: .color(hue(0.1)))

        // Liquid body: a round core, a soft bulge toward the cursor, and droplets churning
        // just under the surface. Everything stays close to the core so the silhouette is a
        // round, wobbling drop rather than a pointy blob.
        var blobs = [ellipse(c, r * sx, r * sy)]
        let podReach = r * 0.28 * (0.6 + 0.4 * p.energy)
        let pod = CGPoint(x: c.x + p.look.dx * podReach, y: c.y + p.look.dy * podReach * 0.6)
        blobs.append(ellipse(pod, r * 0.62, r * 0.62))
        for i in 0..<3 {
            let a = p.phase * 0.7 + Double(i) * 2.094
            let orbit = r * (0.38 + 0.22 * p.energy + 0.06 * CGFloat(sin(p.phase * 0.9 + Double(i))))
            let dropR = r * (0.5 + 0.05 * CGFloat(sin(p.phase * 1.7 + Double(i) * 1.3)))
            let center = CGPoint(x: c.x + CGFloat(cos(a)) * orbit,
                                 y: c.y + CGFloat(sin(a)) * orbit * 0.85)
            blobs.append(ellipse(center, dropR, dropR))
        }

        let bounds = Path(CGRect(origin: .zero, size: size))
        ctx.drawLayer { layer in
            layer.drawLayer { goo in
                goo.addFilter(.alphaThreshold(min: 0.5, color: .white))
                goo.addFilter(.blur(radius: 3 * k))
                goo.drawLayer { shapes in
                    for blob in blobs { shapes.fill(blob, with: .color(.white)) }
                }
            }
            // Paint the rainbow only where the goo is.
            layer.blendMode = .sourceAtop
            let colors = stride(from: 0.0, through: 1.0, by: 0.2).map { hue($0) }
            layer.fill(bounds, with: .conicGradient(Gradient(colors: colors),
                                                    center: c, angle: .radians((p.time * 0.9).truncatingRemainder(dividingBy: 2 * .pi))))
            // Lit from above, shaded below, so it reads as a droplet.
            layer.fill(bounds, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.3), .clear, .black.opacity(0.35)]),
                startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)))
        }

        // Specular highlight.
        ctx.fill(ellipse(CGPoint(x: c.x - r * 0.45, y: c.y - r * 0.55), r * 0.22, r * 0.12),
                 with: .color(.white.opacity(0.6)))

        drawEyes(p, in: &ctx, center: c, r: r, k: k)

        if p.asleep {
            let z = (p.time * 0.5).truncatingRemainder(dividingBy: 1)
            ctx.opacity = 1 - z
            ctx.draw(Text("z").font(.system(size: 4 * k + 3, weight: .heavy, design: .rounded))
                        .foregroundColor(.white),
                     at: CGPoint(x: c.x + r * 0.9 + z * 4 * k, y: c.y - r * 0.6 - z * 8 * k))
        }
    }

    private static func drawEyes(_ p: PetPose, in ctx: inout GraphicsContext,
                                 center c: CGPoint, r: CGFloat, k: CGFloat) {
        let eyeY = c.y - r * 0.12 + p.look.dy * r * 0.16
        let ew = r * 0.34, eh = r * 0.44
        let line = StrokeStyle(lineWidth: max(1, 0.9 * k), lineCap: .round)

        for side: CGFloat in [-1, 1] {
            let e = CGPoint(x: c.x + side * r * 0.38 + p.look.dx * r * 0.22, y: eyeY)

            if p.asleep || p.happy {
                // ‿ when asleep, ^ when happy.
                let lift: CGFloat = p.asleep ? 0.7 : -0.9
                let base = p.asleep ? e.y : e.y + eh * 0.3
                var arc = Path()
                arc.move(to: CGPoint(x: e.x - ew * 0.8, y: base))
                arc.addQuadCurve(to: CGPoint(x: e.x + ew * 0.8, y: base),
                                 control: CGPoint(x: e.x, y: base + eh * lift))
                ctx.stroke(arc, with: .color(.black.opacity(0.75)), style: line)
                continue
            }

            let h = eh * max(0.08, 1 - p.blink)
            ctx.fill(ellipse(e, ew, h), with: .color(.white))
            guard p.blink < 0.6 else { continue }
            let pupil = CGPoint(x: e.x + p.look.dx * ew * 0.4, y: e.y + p.look.dy * h * 0.35)
            ctx.fill(ellipse(pupil, ew * 0.55, min(ew * 0.55, h)), with: .color(.black.opacity(0.85)))
            ctx.fill(ellipse(CGPoint(x: pupil.x - ew * 0.2, y: pupil.y - ew * 0.25), ew * 0.18, ew * 0.18),
                     with: .color(.white))
        }
    }

    private static func ellipse(_ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2))
    }
}
