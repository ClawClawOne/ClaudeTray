import SwiftUI

/// Affichage compact dans la barre de menu : un pourcentage, plus un point discret si périmé.
struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 3) {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(color)
            if store.isStale || store.snapshot == nil {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var text: String {
        guard let window = store.menuBarWindow else { return "—" }
        let value = store.showRemaining ? window.percentRemaining : window.percentUsed
        return UsageFormatting.percent(value)
    }

    private var color: Color {
        guard let window = store.menuBarWindow else { return .secondary }
        // La couleur suit toujours le consommé, même quand le restant est affiché.
        return UsageFormatting.color(forPercentUsed: window.percentUsed)
    }
}
