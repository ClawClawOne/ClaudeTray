import SwiftUI

/// Barre de menu : logo Claude, puis une colonne par fenêtre — intitulé au-dessus,
/// pourcentage en dessous. Hauteur contrainte à celle de la barre (~22 pt),
/// d'où les corps de police fixes et l'interligne nul.
struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 6) {
            // Monochrome : suit l'apparence de la barre de menu (blanc en thème sombre).
            ClaudeGlyph()
                .fill(Color.primary)
                .frame(width: 13, height: 13)

            if store.showBothWindows {
                column(title: "5H", window: store.snapshot?.window(.fiveHour))
                column(title: "WEEK", window: store.snapshot?.window(.sevenDay))
            } else {
                column(title: store.metric.compactLabel, window: store.menuBarWindow)
            }

            if store.isStale || store.snapshot == nil {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func column(title: String, window: UsageWindow?) -> some View {
        VStack(alignment: .center, spacing: -1) {
            Text(title)
                .font(.system(size: 7.5, weight: .semibold))
                .kerning(0.3)
                .foregroundStyle(.secondary)
            Text(value(for: window))
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(color(for: window))
                .monospacedDigit()
        }
        .fixedSize()
    }

    private func value(for window: UsageWindow?) -> String {
        guard let window else { return "—" }
        return UsageFormatting.percentCompact(store.showRemaining ? window.percentRemaining : window.percentUsed)
    }

    private func color(for window: UsageWindow?) -> Color {
        guard let window else { return .secondary }
        // La couleur suit toujours le consommé, même quand le restant est affiché.
        return UsageFormatting.color(forPercentUsed: window.percentUsed, base: store.percentColor)
    }
}
