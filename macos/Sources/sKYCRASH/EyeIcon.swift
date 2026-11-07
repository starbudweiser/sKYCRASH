// L'œil de l'icône sKYCRASH, dessiné en vectoriel pour le splash (reprise de l'animation de la version d'origine) :
// le blanc se pose avec rebond, l'iris orange arrive en tourbillon. « Réduire les animations » : œil fixe.
import AppKit
import SwiftUI

struct AnimatedEyeIcon: View {
    @State private var start = Date()
    private let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduce)) { ctx in
            let t = reduce ? 3000 : ctx.date.timeIntervalSince(start) * 1000
            Canvas { g, size in Self.draw(&g, size, t) }
        }
    }

    // courbes cubic-bezier comme les animations CSS
    private static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> (Double) -> Double {
        func c(_ t: Double, _ a: Double, _ b: Double) -> Double { 3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t }
        return { x in
            if x <= 0 { return 0 }; if x >= 1 { return 1 }
            var lo = 0.0, hi = 1.0
            for _ in 0..<30 { let m = (lo + hi) / 2; if c(m, x1, x2) < x { lo = m } else { hi = m } }
            return c((lo + hi) / 2, y1, y2)
        }
    }
    private static let easeIris = bezier(0.22, 1, 0.36, 1)
    private static let easeWhite = bezier(0.34, 1.3, 0.5, 1)
    private static func phase(_ t: Double, _ start: Double, _ dur: Double) -> Double { min(1, max(0, (t - start) / dur)) }

    /// Blanc de l'œil (repère 1024 × 1024 de l'icône) : disque coupé par la paupière.
    private static let white: Path = {
        let disc = Path(ellipseIn: CGRect(x: 509 - 262, y: 523 - 262, width: 524, height: 524))
        var lid = Path()
        lid.move(to: CGPoint(x: 240, y: 352))
        lid.addCurve(to: CGPoint(x: 640, y: 372), control1: CGPoint(x: 380, y: 278), control2: CGPoint(x: 560, y: 288))
        lid.addCurve(to: CGPoint(x: 776, y: 472), control1: CGPoint(x: 690, y: 422), control2: CGPoint(x: 720, y: 470))
        lid.addLine(to: CGPoint(x: 800, y: 800))
        lid.addLine(to: CGPoint(x: 220, y: 800))
        lid.closeSubpath()
        return disc.intersection(lid)
    }()

    private static func draw(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let s = size.width / 524
        // l'œil (524 unités de large) occupe toute la largeur
        g.translateBy(x: size.width / 2, y: size.height / 2)
        g.scaleBy(x: s, y: s)
        g.translateBy(x: -509, y: -523 + 26)

        let sw = 0.3 + 0.7 * easeWhite(phase(t, 150, 1500))
        g.translateBy(x: 509, y: 523)
        g.scaleBy(x: sw, y: sw)
        g.translateBy(x: -509, y: -523)
        g.opacity = phase(t, 150, 450)
        g.fill(white, with: .color(.white))

        g.clip(to: white)
        let ki = phase(t, 0, 1300)
        let e = easeIris(ki)
        g.opacity = min(1, ki / 0.4) * phase(t, 150, 450)
        g.translateBy(x: 510, y: 473)
        g.scaleBy(x: 0.2 + 0.8 * e, y: 0.2 + 0.8 * e)
        g.rotate(by: .degrees(-420 * (1 - e)))
        func disc(_ x: Double, _ y: Double, _ r: Double, _ c: Color) { g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(c)) }
        disc(0, 0, 162, Color(red: 1, green: 0.478, blue: 0))
        disc(0, 0, 102, Color(red: 0.122, green: 0.071, blue: 0.031))
        disc(90, -48, 30, .white)
        disc(61, -90, 13, .white)
    }
}
