//
//  HalloweenProfileDecoration.swift
//  damus
//
//  Created by Hasky on 10/3/26.
//

import SwiftUI

/// Shared look and timing for the Halloween profile decoration (Damus Labs).
enum HalloweenTheme {
    /// Pumpkin orange, #FF7A00.
    static let orange = Color(red: 1.0, green: 122.0 / 255.0, blue: 0.0)
    static let ringWidth: CGFloat = 3.0
    /// Length of one full pulse of the avatar ring, in seconds.
    static let pulseDuration: Double = 2.5
}

/// A gradient ring drawn just outside a profile picture that slowly pulses.
///
/// The ring is static when Reduce Motion is enabled or when `paused` is true.
struct HalloweenAvatarRing: View {
    /// Diameter of the profile picture the ring surrounds.
    let size: CGFloat
    /// Width of the picture's existing border, so the ring sits outside it.
    let borderWidth: CGFloat
    /// Stops the pulse, e.g. while the profile page is off screen.
    let paused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The picture's border is stroked on the circle's edge, so half of it sits outside.
    private var diameter: CGFloat {
        size + borderWidth + HalloweenTheme.ringWidth * 2
    }

    var body: some View {
        SwiftUI.TimelineView(.animation(paused: paused || reduceMotion)) { timeline in
            ring(pulse: reduceMotion ? 1.0 : Self.pulse(at: timeline.date))
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Eased 0...1...0 value derived from wall-clock time, completing one cycle
    /// every `pulseDuration` seconds. Cosine gives the ease-in-out shape.
    static func pulse(at date: Date) -> Double {
        let cycles = date.timeIntervalSinceReferenceDate / HalloweenTheme.pulseDuration
        return (1.0 - cos(cycles * 2.0 * .pi)) / 2.0
    }

    /// Ring opacity for a pulse value: 0.6 at rest, 1.0 at the peak.
    static func opacity(for pulse: Double) -> Double {
        0.6 + 0.4 * pulse
    }

    /// Ring scale for a pulse value: 1.0 at rest, 1.04 at the peak.
    static func scale(for pulse: Double) -> CGFloat {
        1.0 + 0.04 * CGFloat(pulse)
    }

    private func ring(pulse: Double) -> some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: [HalloweenTheme.orange, DamusColors.purple, HalloweenTheme.orange],
                    center: .center
                ),
                lineWidth: HalloweenTheme.ringWidth
            )
            .opacity(Self.opacity(for: pulse))
            .scaleEffect(Self.scale(for: pulse))
            .shadow(color: HalloweenTheme.orange.opacity(0.6 * pulse), radius: 4.0 * pulse)
    }
}

/// Bats and pumpkins that drift down over a profile banner with a slight sway.
///
/// Everything is drawn in a single `Canvas` driven by a `TimelineView`, so there is
/// no per-particle view. Nothing is drawn when Reduce Motion is enabled.
struct HalloweenBannerParticles: View {
    /// Stops the drift, e.g. while the profile page is off screen.
    let paused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    for particle in HalloweenParticle.all {
                        particle.draw(in: &context, canvasSize: size, time: time)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// One drifting bat or pumpkin. Particles are fixed so the layout is stable between frames.
struct HalloweenParticle {
    enum Kind {
        case bat
        case pumpkin
    }

    let kind: Kind
    /// Horizontal resting position as a fraction of the banner width.
    let x: CGFloat
    /// Seconds to fall from the top of the banner to the bottom.
    let fallDuration: Double
    /// Offset into the fall cycle, in seconds, so particles don't move in lockstep.
    let timeOffset: Double
    let size: CGFloat
    /// Maximum sideways sway, in points.
    let swayAmplitude: CGFloat
    /// Sway cycles per second.
    let swaySpeed: Double

    static let all: [HalloweenParticle] = [
        HalloweenParticle(kind: .bat, x: 0.08, fallDuration: 9.0, timeOffset: 0.0, size: 16, swayAmplitude: 10, swaySpeed: 0.35),
        HalloweenParticle(kind: .pumpkin, x: 0.20, fallDuration: 11.0, timeOffset: 6.5, size: 13, swayAmplitude: 6, swaySpeed: 0.25),
        HalloweenParticle(kind: .bat, x: 0.31, fallDuration: 8.0, timeOffset: 3.0, size: 13, swayAmplitude: 12, swaySpeed: 0.45),
        HalloweenParticle(kind: .pumpkin, x: 0.43, fallDuration: 10.0, timeOffset: 1.5, size: 15, swayAmplitude: 5, swaySpeed: 0.3),
        HalloweenParticle(kind: .bat, x: 0.52, fallDuration: 9.5, timeOffset: 7.0, size: 18, swayAmplitude: 9, swaySpeed: 0.4),
        HalloweenParticle(kind: .pumpkin, x: 0.63, fallDuration: 12.0, timeOffset: 4.0, size: 12, swayAmplitude: 7, swaySpeed: 0.22),
        HalloweenParticle(kind: .bat, x: 0.72, fallDuration: 8.5, timeOffset: 5.5, size: 14, swayAmplitude: 11, swaySpeed: 0.5),
        HalloweenParticle(kind: .pumpkin, x: 0.82, fallDuration: 10.5, timeOffset: 2.5, size: 14, swayAmplitude: 6, swaySpeed: 0.28),
        HalloweenParticle(kind: .bat, x: 0.91, fallDuration: 9.0, timeOffset: 8.0, size: 15, swayAmplitude: 10, swaySpeed: 0.38),
        HalloweenParticle(kind: .pumpkin, x: 0.97, fallDuration: 11.5, timeOffset: 9.5, size: 11, swayAmplitude: 5, swaySpeed: 0.3),
    ]

    /// Draws the particle at its position for `time`, fading in at the top and out near the bottom.
    func draw(in context: inout GraphicsContext, canvasSize: CGSize, time: Double) {
        let cycle = (time + timeOffset) / fallDuration
        let progress = CGFloat(cycle - floor(cycle))

        let y = -size + progress * (canvasSize.height + size * 2)
        let swayPhase = time * swaySpeed * 2.0 * .pi + timeOffset
        let x = x * canvasSize.width + CGFloat(sin(swayPhase)) * swayAmplitude

        let fadeIn = min(1.0, progress / 0.1)
        let fadeOut = min(1.0, (1.0 - progress) / 0.35)

        var particleContext = context
        particleContext.opacity = 0.9 * Double(min(fadeIn, fadeOut))
        particleContext.translateBy(x: x, y: y)
        // Tilt with the sway so the drift reads as floating rather than sliding.
        particleContext.rotate(by: .radians(cos(swayPhase) * 0.25))

        switch kind {
        case .bat:
            particleContext.fill(Self.batPath(size: size), with: .color(.black))
        case .pumpkin:
            Self.drawPumpkin(in: &particleContext, size: size)
        }
    }

    /// A simple bat silhouette centered on the origin, `size` points wide.
    static func batPath(size: CGFloat) -> Path {
        let w = size / 2.0
        let h = size * 0.3
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -h * 0.5))
        // Right wing, scalloped along the bottom edge.
        path.addQuadCurve(to: CGPoint(x: w, y: -h), control: CGPoint(x: w * 0.5, y: -h * 1.3))
        path.addQuadCurve(to: CGPoint(x: w * 0.6, y: h * 0.5), control: CGPoint(x: w * 0.85, y: h * 0.1))
        path.addQuadCurve(to: CGPoint(x: w * 0.25, y: h * 0.4), control: CGPoint(x: w * 0.4, y: h * 0.1))
        path.addQuadCurve(to: CGPoint(x: 0, y: h * 0.7), control: CGPoint(x: w * 0.1, y: h * 0.4))
        // Left wing, mirrored.
        path.addQuadCurve(to: CGPoint(x: -w * 0.25, y: h * 0.4), control: CGPoint(x: -w * 0.1, y: h * 0.4))
        path.addQuadCurve(to: CGPoint(x: -w * 0.6, y: h * 0.5), control: CGPoint(x: -w * 0.4, y: h * 0.1))
        path.addQuadCurve(to: CGPoint(x: -w, y: -h), control: CGPoint(x: -w * 0.85, y: h * 0.1))
        path.addQuadCurve(to: CGPoint(x: 0, y: -h * 0.5), control: CGPoint(x: -w * 0.5, y: -h * 1.3))
        path.closeSubpath()
        // Head with ears.
        path.move(to: CGPoint(x: -w * 0.12, y: -h * 0.4))
        path.addLine(to: CGPoint(x: -w * 0.1, y: -h * 1.1))
        path.addLine(to: CGPoint(x: 0, y: -h * 0.75))
        path.addLine(to: CGPoint(x: w * 0.1, y: -h * 1.1))
        path.addLine(to: CGPoint(x: w * 0.12, y: -h * 0.4))
        path.closeSubpath()
        return path
    }

    /// A pumpkin centered on the origin: three overlapping lobes and a green stem.
    static func drawPumpkin(in context: inout GraphicsContext, size: CGFloat) {
        let height = size * 0.8
        let lobeWidth = size * 0.5
        for lobeX in [-size * 0.25, size * 0.25, 0] {
            let lobe = CGRect(x: lobeX - lobeWidth / 2.0, y: -height / 2.0, width: lobeWidth, height: height)
            context.fill(Path(ellipseIn: lobe), with: .color(HalloweenTheme.orange))
            context.stroke(Path(ellipseIn: lobe), with: .color(.black.opacity(0.25)), lineWidth: 0.5)
        }
        let stem = CGRect(x: -size * 0.06, y: -height / 2.0 - size * 0.18, width: size * 0.12, height: size * 0.22)
        context.fill(Path(roundedRect: stem, cornerRadius: size * 0.03), with: .color(.green.opacity(0.8)))
    }
}

#Preview {
    ZStack {
        Color.gray
        HalloweenBannerParticles(paused: false)
    }
    .frame(height: 150)
}

// MARK: - Pumpkin like button

/// Stands in for the shaka like button while the Halloween lab is on.
/// `lit` shows a carved face once the note is liked; bump `burst` to spit candy.
struct HalloweenPumpkinLike: View {
    let lit: Bool
    let burst: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var candies: [HalloweenCandy] = []
    @State private var squish = false
    @State private var glow = false

    var body: some View {
        ZStack {
            ForEach(candies) { candy in
                HalloweenCandyView(candy: candy)
            }
            Canvas { context, size in
                var pumpkin = context
                pumpkin.translateBy(x: size.width / 2.0, y: size.height / 2.0 + 1.0)
                HalloweenParticle.drawPumpkin(in: &pumpkin, size: size.width)
                if lit {
                    Self.drawFace(in: &pumpkin, size: size.width)
                }
            }
            .frame(width: 22, height: 20)
            .scaleEffect(squish ? 0.7 : 1.0)
            .shadow(color: HalloweenTheme.orange.opacity(glow ? 0.9 : 0), radius: glow ? 10 : 0)
        }
        .onChange(of: burst) { _ in
            spitCandy()
        }
    }

    private func spitCandy() {
        withAnimation(.easeOut(duration: 0.1)) { squish = true }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.4).delay(0.1)) { squish = false }
        withAnimation(.easeOut(duration: 0.15)) { glow = true }
        withAnimation(.easeIn(duration: 0.6).delay(0.2)) { glow = false }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        guard !reduceMotion else { return }
        let fresh = (0..<14).map { _ in HalloweenCandy.random() }
        candies.append(contentsOf: fresh)
        let ids = Set(fresh.map(\.id))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            candies.removeAll { ids.contains($0.id) }
        }
    }

    /// Jack-o'-lantern face: two triangle eyes and a jagged grin.
    static func drawFace(in context: inout GraphicsContext, size: CGFloat) {
        let dark = Color.black.opacity(0.8)
        var eyes = Path()
        for sign in [-1.0, 1.0] {
            let cx = CGFloat(sign) * size * 0.18
            eyes.move(to: CGPoint(x: cx, y: -size * 0.22))
            eyes.addLine(to: CGPoint(x: cx + size * 0.1, y: -size * 0.05))
            eyes.addLine(to: CGPoint(x: cx - size * 0.1, y: -size * 0.05))
            eyes.closeSubpath()
        }
        context.fill(eyes, with: .color(dark))

        var grin = Path()
        grin.move(to: CGPoint(x: -size * 0.28, y: size * 0.08))
        grin.addLine(to: CGPoint(x: -size * 0.16, y: size * 0.2))
        grin.addLine(to: CGPoint(x: -size * 0.06, y: size * 0.1))
        grin.addLine(to: CGPoint(x: size * 0.06, y: size * 0.2))
        grin.addLine(to: CGPoint(x: size * 0.16, y: size * 0.1))
        grin.addLine(to: CGPoint(x: size * 0.28, y: size * 0.08))
        grin.addLine(to: CGPoint(x: 0, y: size * 0.3))
        grin.closeSubpath()
        context.fill(grin, with: .color(dark))
    }
}

/// One piece of candy flying out of the pumpkin.
struct HalloweenCandy: Identifiable {
    enum Kind {
        case wrapped
        case lollipop
        case sparkle
    }

    let id = UUID()
    let kind: Kind
    let color: Color
    /// Where it lands, relative to the pumpkin.
    let dx: CGFloat
    let dy: CGFloat
    let spin: Double

    static func random() -> HalloweenCandy {
        let colors: [Color] = [HalloweenTheme.orange, DamusColors.purple, .white, .pink, .yellow, .green]
        return HalloweenCandy(
            kind: [.wrapped, .lollipop, .sparkle, .sparkle].randomElement() ?? .wrapped,
            color: colors.randomElement() ?? HalloweenTheme.orange,
            dx: CGFloat.random(in: -44...44),
            dy: CGFloat.random(in: -60 ... -16),
            spin: Double.random(in: -400...400))
    }
}

struct HalloweenCandyView: View {
    let candy: HalloweenCandy
    @State private var flown = false

    var body: some View {
        Group {
            switch candy.kind {
            case .wrapped:
                HStack(spacing: 0) {
                    Triangle().frame(width: 3, height: 4)
                    Capsule().frame(width: 7, height: 4)
                    Triangle().rotationEffect(.degrees(180)).frame(width: 3, height: 4)
                }
            case .lollipop:
                VStack(spacing: 0) {
                    Circle().frame(width: 7, height: 7)
                    Rectangle().fill(.white.opacity(0.8)).frame(width: 1, height: 5)
                }
            case .sparkle:
                Sparkle().frame(width: 8, height: 8)
            }
        }
        .foregroundColor(candy.color)
        .shadow(color: candy.color.opacity(0.9), radius: 3)
        .shadow(color: .black.opacity(0.25), radius: 0.5)
        .rotationEffect(.degrees(flown ? candy.spin : 0))
        .offset(x: flown ? candy.dx : 0, y: flown ? candy.dy : 0)
        .opacity(flown ? 0 : 1)
        .scaleEffect(flown ? 1.3 : 0.2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.interpolatingSpring(stiffness: 60, damping: 9).speed(0.9)) {
                flown = true
            }
        }
    }

    private struct Sparkle: Shape {
        func path(in rect: CGRect) -> Path {
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r = rect.width / 2.0
            var path = Path()
            for i in 0..<8 {
                let angle = Double(i) * .pi / 4.0
                let radius = i % 2 == 0 ? r : r * 0.35
                let point = CGPoint(x: c.x + CGFloat(cos(angle)) * radius, y: c.y + CGFloat(sin(angle)) * radius)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

#Preview("Pumpkin like") {
    HStack(spacing: 40) {
        HalloweenPumpkinLike(lit: false, burst: 0)
        HalloweenPumpkinLike(lit: true, burst: 0)
    }
    .padding(40)
}
