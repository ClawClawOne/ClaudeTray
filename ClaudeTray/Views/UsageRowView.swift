import SwiftUI

/// Une fenêtre de quota : titre, pourcentage, barre de progression, compte à rebours.
struct UsageRowView: View {
    let window: UsageWindow
    let now: Date
    let showRemaining: Bool
    let baseColor: Color
    let loc: Loc

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title(loc))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(UsageFormatting.percent(showRemaining ? window.percentRemaining : window.percentUsed))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(UsageFormatting.color(forPercentUsed: window.percentUsed, base: baseColor))
            }

            ProgressView(value: window.percentUsed, total: 100)
                .progressViewStyle(.linear)
                .tint(UsageFormatting.color(forPercentUsed: window.percentUsed, base: baseColor))

            // Aucun reset n'est calculé localement : on n'affiche que ce que l'API renvoie.
            if let resetsAt = window.resetsAt {
                Text(loc.resetIn(UsageFormatting.countdown(to: resetsAt, from: now, loc: loc)))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text(loc.resetUnknown)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
