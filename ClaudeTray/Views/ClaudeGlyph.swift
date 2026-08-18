import SwiftUI

/// Logo Claude : une rosace de rayons effilés partant d'un centre commun.
/// Dessiné en `Path` plutôt qu'importé en asset — aucune ressource à embarquer,
/// et le rendu reste net à toutes les tailles de barre de menu.
struct ClaudeGlyph: Shape {
    /// Angles des rayons, en degrés. Répartition irrégulière fidèle au logo.
    private let angles: [Double] = [0, 33, 66, 99, 132, 165, 198, 231, 264, 297, 330]

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.16
        let halfWidthAtCenter = outer * 0.115
        let halfWidthAtTip = outer * 0.045

        var path = Path()
        for angle in angles {
            let radians = angle * .pi / 180
            let direction = CGVector(dx: cos(radians), dy: sin(radians))
            let normal = CGVector(dx: -direction.dy, dy: direction.dx)

            func point(radius: Double, offset: Double) -> CGPoint {
                CGPoint(x: center.x + direction.dx * radius + normal.dx * offset,
                        y: center.y + direction.dy * radius + normal.dy * offset)
            }

            path.move(to: point(radius: inner, offset: halfWidthAtCenter))
            path.addLine(to: point(radius: outer, offset: halfWidthAtTip))
            path.addLine(to: point(radius: outer, offset: -halfWidthAtTip))
            path.addLine(to: point(radius: inner, offset: -halfWidthAtCenter))
            path.closeSubpath()
        }
        return path
    }
}

/// Couleur de marque Claude.
extension Color {
    static let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
}
