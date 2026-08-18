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

        if let image = rendered() {
            Image(nsImage: image)
        } else {
            Text(fallbackText)
        }
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
            ClaudeGlyph()
                .fill(monochrome)
                .frame(width: 14, height: 14)
                .padding(.trailing, 5)   // respiration supplémentaire entre le logo et les données

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

            if store.isStale || store.snapshot == nil {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(monochrome.opacity(0.6))
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 22)
        .fixedSize()
    }

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

    private var fallbackText: String {
        guard let window = store.menuBarWindow else { return "—" }
        return UsageFormatting.percentCompact(window.percentUsed)
    }

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
