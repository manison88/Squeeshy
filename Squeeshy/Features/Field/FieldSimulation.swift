import SwiftUI

/// A force simulation, not a layout pass. Each squeeshy is pulled toward the centre
/// in proportion to how well it matches the slider and pushed to the rim when it
/// doesn't, and they collide off each other on the way. Dragging the slider stirs
/// the field rather than re-drawing it.
@Observable
final class FieldSimulation {

    struct Bubble: Identifiable {
        let id: UUID
        var squishy: Squishy
        var color: Color
        var name: String
        var traitValue: Double

        var x: Double = 0
        var y: Double = 0
        var vx: Double = 0
        var vy: Double = 0
        /// Current drawn diameter, itself a spring so growth overshoots.
        var diameter: Double = 60
        var targetDiameter: Double = 60
        /// 0...1 match against the current slider position.
        var match: Double = 0.5
    }

    private(set) var bubbles: [Bubble] = []
    var size: CGSize = .zero

    /// Sized from the field rather than fixed, so a shelf fills an iPad instead of
    /// sitting in the middle of it as a handful of phone-sized dots. Clamped at the top
    /// so a 13-inch screen does not turn six squeeshies into six beach balls, and at
    /// the bottom so a narrow Split View column stays legible.
    ///
    /// The old constants were 46 and 104, which is what these produce on a phone.
    private var shortSide: Double { max(1, min(size.width, size.height)) }
    private var minDiameter: Double { min(84, max(46, shortSide * 0.125)) }
    private var maxDiameter: Double { min(190, max(104, shortSide * 0.28)) }

    // MARK: Setup

    func load(_ items: [Squishy], trait: Trait) {
        bubbles = items.enumerated().map { i, s in
            var b = Bubble(id: s.id, squishy: s, color: s.color,
                           name: s.name, traitValue: trait.value(of: s))
            // Golden-angle spiral seed: converges fast and symmetrically, where a
            // ring seed leaves a permanent hole in the middle.
            let angle = Double(i) * 2.399963
            let radius = (Double(i) / Double(max(1, items.count))).squareRoot()
            b.x = 0.5 + cos(angle) * radius * 0.30
            b.y = 0.5 + sin(angle) * radius * 0.26
            return b
        }
    }

    func updateTraitValues(_ items: [Squishy], trait: Trait) {
        for i in bubbles.indices {
            if let match = items.first(where: { $0.id == bubbles[i].id }) {
                bubbles[i].traitValue = trait.value(of: match)
            }
        }
    }

    /// Recomputes how well every bubble matches the slider. Called on every slider
    /// frame; the sizes and positions then chase these targets.
    func score(domain: TraitDomain, sliderValue: Double) {
        for i in bubbles.indices {
            let m = domain.match(bubbles[i].traitValue, sliderValue: sliderValue)
            bubbles[i].match = m
            bubbles[i].targetDiameter = minDiameter + (maxDiameter - minDiameter) * m
        }
    }

    var matchCount: Int { bubbles.filter { $0.match > 0.55 }.count }

    // MARK: Step

    func step(dt: Double) {
        guard size.width > 1, !bubbles.isEmpty else { return }
        let w = size.width, h = size.height
        let cx = w / 2, cy = h / 2

        for i in bubbles.indices {
            bubbles[i].diameter += (bubbles[i].targetDiameter - bubbles[i].diameter) * min(1, dt * 13)

            let px = bubbles[i].x * w, py = bubbles[i].y * h
            let dx = cx - px, dy = cy - py
            let d = max(1, (dx * dx + dy * dy).squareRoot())

            // Positive draws inward, negative pushes to the rim. Scaling by distance
            // lets it settle instead of orbiting forever.
            let force = (bubbles[i].match - 0.42) * 900 * min(1, d / 150)
            bubbles[i].vx += (dx / d) * force * dt
            bubbles[i].vy += (dy / d) * force * dt
            bubbles[i].vx *= 0.86
            bubbles[i].vy *= 0.86
        }

        resolveCollisions(w: w, h: h)

        for i in bubbles.indices {
            var b = bubbles[i]
            b.x += (b.vx * dt) / w
            b.y += (b.vy * dt) / h

            let rx = (b.diameter / 2) / w
            let ry = (b.diameter / 2) / h
            if b.x < rx { b.x = rx; b.vx *= -0.4 }
            if b.x > 1 - rx { b.x = 1 - rx; b.vx *= -0.4 }
            if b.y < ry { b.y = ry; b.vy *= -0.4 }
            if b.y > 1 - ry { b.y = 1 - ry; b.vy *= -0.4 }
            bubbles[i] = b
        }
    }

    private func resolveCollisions(w: Double, h: Double) {
        guard bubbles.count > 1 else { return }
        for i in 0..<(bubbles.count - 1) {
            for j in (i + 1)..<bubbles.count {
                let ax = bubbles[i].x * w, ay = bubbles[i].y * h
                let bx = bubbles[j].x * w, by = bubbles[j].y * h
                let ox = bx - ax, oy = by - ay
                let dist = max(0.01, (ox * ox + oy * oy).squareRoot())
                let minimum = (bubbles[i].diameter + bubbles[j].diameter) / 2 + 4
                guard dist < minimum else { continue }

                let overlap = (minimum - dist) / dist * 0.5
                let sx = ox * overlap, sy = oy * overlap
                bubbles[i].x -= sx / w; bubbles[i].y -= sy / h
                bubbles[j].x += sx / w; bubbles[j].y += sy / h
                bubbles[i].vx -= sx * 5; bubbles[i].vy -= sy * 5
                bubbles[j].vx += sx * 5; bubbles[j].vy += sy * 5
            }
        }
    }

    /// Manual hit testing, because the whole field is a single Canvas.
    func bubble(at point: CGPoint) -> UUID? {
        for b in bubbles.reversed() {
            let dx = b.x * size.width - point.x
            let dy = b.y * size.height - point.y
            if (dx * dx + dy * dy).squareRoot() < b.diameter / 2 { return b.id }
        }
        return nil
    }
}
