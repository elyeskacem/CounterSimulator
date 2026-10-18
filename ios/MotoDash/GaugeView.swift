import SwiftUI

/// Speedometer: a 240° arc from 0 to 160 km/h with the speed in the middle.
/// Drawn in a 300 x 230 design space (same geometry as the web version) and scaled to fit.
struct GaugeView: View {
    let speed: Double

    private let maxSpeed = 160.0
    private let center = CGPoint(x: 150, y: 140)
    private let radius = 110.0
    private let startDeg = 150.0
    private let sweepDeg = 240.0

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / 300
            ZStack {
                Canvas { ctx, _ in
                    ctx.scaleBy(x: scale, y: scale)
                    drawGauge(&ctx)
                }
                VStack(spacing: 0) {
                    Text("\(Int(speed.rounded()))")
                        .font(.system(size: 76 * scale, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundColor(.white)
                    Text("km/h")
                        .font(.system(size: 14 * scale, weight: .medium))
                        .tracking(2)
                        .foregroundColor(Theme.muted)
                }
                .position(x: geo.size.width / 2, y: 150 * scale)
            }
        }
        .aspectRatio(300.0 / 230.0, contentMode: .fit)
        .frame(maxWidth: 380)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speed \(Int(speed.rounded())) kilometres per hour")
    }

    private func point(_ r: Double, _ deg: Double) -> CGPoint {
        let a = deg * .pi / 180
        return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
    }

    private func arc(_ r: Double, from: Double, to: Double) -> Path {
        var path = Path()
        let steps = max(2, Int(abs(to - from) / 2))
        path.move(to: point(r, from))
        for i in 1...steps {
            let deg = from + (to - from) * Double(i) / Double(steps)
            path.addLine(to: point(r, deg))
        }
        return path
    }

    private func drawGauge(_ ctx: inout GraphicsContext) {
        let round = StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round)

        // Track
        ctx.stroke(arc(radius, from: startDeg, to: startDeg + sweepDeg),
                   with: .color(Color(hex: 0x1A2029)), style: round)

        // Value (green -> yellow -> red, fixed across the whole gauge)
        let fraction = min(max(speed / maxSpeed, 0), 1)
        if fraction > 0.004 {
            let gradient = Gradient(stops: [
                .init(color: Theme.accent, location: 0),
                .init(color: Theme.warn, location: 0.6),
                .init(color: Theme.danger, location: 1)
            ])
            ctx.stroke(arc(radius, from: startDeg, to: startDeg + fraction * sweepDeg),
                       with: .linearGradient(gradient, startPoint: CGPoint(x: 40, y: 0), endPoint: CGPoint(x: 260, y: 0)),
                       style: round)
        }

        // Ticks and numbers
        var v = 0
        while v <= Int(maxSpeed) {
            let deg = startDeg + Double(v) / maxSpeed * sweepDeg
            let major = v % 20 == 0
            var tick = Path()
            tick.move(to: point(radius - 14, deg))
            tick.addLine(to: point(radius - (major ? 24 : 19), deg))
            ctx.stroke(tick,
                       with: .color(major ? Color(hex: 0x6B7684) : Color(hex: 0x3A4350)),
                       style: StrokeStyle(lineWidth: major ? 3 : 2))
            if major {
                let label = Text("\(v)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.muted)
                ctx.draw(label, at: point(radius - 36, deg), anchor: .center)
            }
            v += 10
        }
    }
}
