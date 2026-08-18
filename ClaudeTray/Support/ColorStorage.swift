import AppKit
import SwiftUI

/// Persistance de la couleur choisie pour les pourcentages, en hexadécimal sRGB.
enum ColorStorage {
    /// Vert par défaut, comme sur les afficheurs de mesure.
    static let defaultPercentColor = Color(red: 0.29, green: 0.87, blue: 0.30)

    /// Palette proposée dans le popover. Un `ColorPicker` y ouvrirait `NSColorPanel`,
    /// ce qui referme le popover de la barre de menu et rend le choix impossible :
    /// des pastilles cliquables sont le seul mécanisme qui fonctionne à cet endroit.
    static let palette: [(key: String, color: Color)] = [
        ("green", defaultPercentColor),
        ("cyan", Color(red: 0.20, green: 0.82, blue: 0.92)),
        ("blue", Color(red: 0.31, green: 0.60, blue: 1.00)),
        ("purple", Color(red: 0.71, green: 0.55, blue: 1.00)),
        ("pink", Color(red: 1.00, green: 0.45, blue: 0.72)),
        ("yellow", Color(red: 1.00, green: 0.83, blue: 0.25)),
        ("orange", Color(red: 0.85, green: 0.47, blue: 0.34)),
        ("white", Color.white),
    ]

    static func hex(from color: Color) -> String {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return "4ADE4D" }
        let components = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
        return components
            .map { String(format: "%02X", Int((min(max($0, 0), 1) * 255).rounded())) }
            .joined()
    }

    static func color(fromHex hex: String?) -> Color? {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}
