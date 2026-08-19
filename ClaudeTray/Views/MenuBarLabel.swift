import AppKit
import SwiftUI

/// Barre de menu : logo Claude monochrome, puis une colonne par fenêtre —
/// intitulé en capitales au-dessus, pourcentage consommé en dessous.
///
/// `MenuBarExtra` n'affiche pas correctement une vue composée sur deux lignes : il la réduit
/// à son premier élément. La vue est donc rasterisée avec `ImageRenderer` et fournie comme
/// simple `Image`, ce que `MenuBarExtra` place tel quel. Contrepartie : le mode clair/sombre
/// est résolu à la main (`NSApp.effectiveAppearance`) au lieu d'être hérité.
struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        // Dépendance explicite à l'horloge : force un rendu par seconde, ce qui suffit à
        // rattraper un changement d'apparence système et l'animation du marqueur d'obsolescence.
        let _ = store.now

        // Toujours la même branche : alterner entre `Image` et `Text` changerait l'identité
        // de la vue du libellé, et `MenuBarExtra` re-présente sa fenêtre à ce moment-là.
        Image(nsImage: rendered() ?? Self.emptyImage)
    }

    // MARK: - Rendu

    @MainActor
    private func rendered() -> NSImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.isOpaque = false
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }

    private var content: some View {
        HStack(spacing: store.itemSpacing) {
            if store.showLogo {
                ClaudeGlyph()
                    .fill(monochrome)
                    .frame(width: 14, height: 14)
                    .padding(.trailing, 5)   // respiration supplémentaire entre le logo et les données
            }

            if store.showBothWindows {
                column(title: "5H", window: store.snapshot?.window(.fiveHour))
                column(title: "WEEK", window: store.snapshot?.window(.sevenDay))
                // Fenêtres par modèle (Fable, Opus…), telles que l'API les nomme.
                ForEach(store.scopedWindows) { window in
                    column(title: window.id.compactTitle, window: window)
                }
            } else {
                column(title: store.metric.compactLabel, window: store.menuBarWindow)
            }

            statusGlyph
        }
        // Marge extérieure propre à l'app, nulle par défaut : ne reste alors que celle que
        // macOS impose lui-même au bouton de la barre de menu. Réglable jusqu'à 24 pt.
        .padding(.horizontal, store.edgeMargin)
        .frame(height: 22)
        .fixedSize()
    }

    /// Emplacement d'état, toujours présent et toujours de la même largeur : une erreur y met
    /// un triangle orange, une donnée obsolète un rond discret, et le reste du temps il est
    /// transparent. Le faire apparaître et disparaître changerait la largeur du libellé, ce qui
    /// suffit à faire rouvrir le popover tout seul.
    private var statusGlyph: some View {
        Image(systemName: store.hasError ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
            .font(.system(size: 9))
            .foregroundStyle(glyphColor)
            .frame(width: 11)
    }

    private var glyphColor: Color {
        if store.hasError { return .orange }
        if store.isStale || store.snapshot == nil { return monochrome.opacity(0.6) }
        return .clear
    }

    /// Image vide de la hauteur de la barre, servie si le rendu échoue : mieux vaut un blanc
    /// qu'un changement de type de vue.
    private static let emptyImage: NSImage = {
        let image = NSImage(size: NSSize(width: 1, height: 22))
        image.isTemplate = false
        return image
    }()

    private func column(title: String, window: UsageWindow?) -> some View {
        // Deux lignes alignées à gauche : intitulé en capitales, pourcentage en dessous.
        VStack(alignment: .leading, spacing: -2.5) {
            Text(title)
                .font(.system(size: 7, weight: .regular))
                .kerning(0.2)
                .foregroundStyle(monochrome)
                .offset(y: 1)
            Text(value(for: window))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color(for: window))
                .monospacedDigit()
        }
        .fixedSize()
        .frame(alignment: .leading)
    }

    // MARK: - Valeurs

    private func value(for window: UsageWindow?) -> String {
        guard let window else { return "—" }
        return UsageFormatting.percentCompact(store.showRemaining ? window.percentRemaining : window.percentUsed)
    }

    private func color(for window: UsageWindow?) -> Color {
        guard let window else { return monochrome.opacity(0.6) }
        // La couleur suit toujours le consommé, même quand le restant est affiché.
        return UsageFormatting.color(forPercentUsed: window.percentUsed, base: store.percentColor)
    }

    /// Blanc en barre de menu sombre, noir en barre claire.
    private var monochrome: Color {
        let isDark = NSApp?.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? .white : .black
    }
}
