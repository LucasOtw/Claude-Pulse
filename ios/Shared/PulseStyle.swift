import SwiftUI

enum PulseStyle {
    /// Orange Claude
    static let accent = Color(red: 0.85, green: 0.47, blue: 0.34)

    static func color(for status: String) -> Color {
        switch status {
        case "running": return accent
        case "waiting": return .yellow
        case "background": return .blue
        case "done": return .green
        case "error": return .red
        default: return .gray
        }
    }

    static func symbol(for status: String) -> String {
        switch status {
        case "running": return "sparkle"
        case "waiting": return "hand.raised.fill"
        case "background": return "hourglass"
        case "done": return "checkmark.circle.fill"
        case "error": return "exclamationmark.triangle.fill"
        default: return "moon.zzz.fill"
        }
    }

    static func label(for status: String) -> String {
        switch status {
        case "running": return "En cours"
        case "waiting": return "Attend ta validation"
        case "background": return "En arrière-plan"
        case "done": return "Terminé"
        case "error": return "Erreur"
        default: return "Inactif"
        }
    }

    static func cost(_ usd: Double) -> String {
        usd.formatted(.currency(code: "USD").locale(Locale(identifier: "fr_FR")))
    }

    /// Couleur d'une jauge de limite : vert, puis orange, puis rouge.
    static func gauge(_ pct: Double) -> Color {
        pct < 60 ? .green : pct < 85 ? .orange : .red
    }
}
