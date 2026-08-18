import SwiftUI

enum UsageFormatting {

    /// Orange à 80 %, rouge à 95 %.
    static func color(forPercentUsed percent: Double) -> Color {
        if percent >= Thresholds.critical { return .red }
        if percent >= Thresholds.warning { return .orange }
        return .primary
    }

    /// Teinte des barres de progression : même seuils, mais toujours colorée.
    static func barColor(forPercentUsed percent: Double) -> Color {
        if percent >= Thresholds.critical { return .red }
        if percent >= Thresholds.warning { return .orange }
        return .accentColor
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded())) %"
    }

    /// Compte à rebours lisible. Affiché uniquement à partir d'un `resets_at` réel.
    static func countdown(to date: Date, from now: Date) -> String {
        let remaining = Int(date.timeIntervalSince(now).rounded())
        guard remaining > 0 else { return "reset imminent" }

        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        let seconds = remaining % 60

        if days > 0 { return "\(days) j \(hours) h \(minutes) min" }
        if hours > 0 { return String(format: "%d h %02d min %02d s", hours, minutes, seconds) }
        return String(format: "%02d min %02d s", minutes, seconds)
    }

    /// Durée courte pour « obsolète depuis X ».
    static func shortDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        if total >= 86_400 { return "\(total / 86_400) j" }
        if total >= 3_600 { return "\(total / 3_600) h" }
        if total >= 60 { return "\(total / 60) min" }
        return "\(total) s"
    }

    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
