import SwiftUI

/// Identité visuelle commune à l'app, au widget et à la Live Activity : noir profond, orange Claude.
enum PulseStyle {
    // MARK: Couleurs

    /// Orange Claude
    static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)
    static let accentSoft = Color(red: 0.965, green: 0.690, blue: 0.541)
    static let background = Color(red: 0.039, green: 0.035, blue: 0.035)
    static let card = Color(red: 0.086, green: 0.082, blue: 0.082)
    static let cardRaised = Color(red: 0.122, green: 0.114, blue: 0.110)
    static let stroke = Color.white.opacity(0.07)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.4)

    static let good = Color(red: 0.36, green: 0.82, blue: 0.53)
    static let warn = Color(red: 0.98, green: 0.76, blue: 0.29)
    static let hot = Color(red: 0.96, green: 0.52, blue: 0.29)
    static let critical = Color(red: 0.94, green: 0.33, blue: 0.31)

    /// Dégradé des jauges de limite : vert → jaune → orange → rouge, sur toute la largeur.
    static let limitGradient = LinearGradient(
        colors: [good, warn, hot, critical],
        startPoint: .leading, endPoint: .trailing
    )

    static func color(for status: String) -> Color {
        switch status {
        case "running": return accent
        case "waiting": return warn
        case "background": return Color(red: 0.42, green: 0.62, blue: 1.0)
        case "done": return good
        case "error": return critical
        default: return Color.white.opacity(0.45)
        }
    }

    static func symbol(for status: String) -> String {
        switch status {
        case "running": return "sparkle"
        case "waiting": return "hand.raised.fill"
        case "background": return "hourglass"
        case "done": return "checkmark"
        case "error": return "exclamationmark.triangle.fill"
        default: return "moon.zzz.fill"
        }
    }

    static func label(for status: String) -> String {
        switch status {
        case "running": return "En cours"
        case "waiting": return "Validation"
        case "background": return "Arrière-plan"
        case "done": return "Terminé"
        case "error": return "Erreur"
        default: return "Inactif"
        }
    }

    /// Couleur d'un pourcentage de limite : vert, puis jaune, orange, rouge.
    static func gauge(_ pct: Double) -> Color {
        switch pct {
        case ..<50: return good
        case ..<75: return warn
        case ..<90: return hot
        default: return critical
        }
    }

    // MARK: Formats

    /// « 12,40 $ » : estimation au tarif de l'API.
    static func cost(_ usd: Double) -> String {
        usd.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "fr_FR"))) + " $"
    }

    /// « 14:00 » aujourd'hui, « mer. 14:00 » au-delà.
    static func resetTime(_ date: Date) -> String {
        let fr = Locale(identifier: "fr_FR")
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute().locale(fr))
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(fr))
    }
}

// MARK: - Composants partagés

/// Grosse barre de limite façon « suivi de course » : dégradé, curseur lumineux au bout.
struct LimitBar: View {
    /// 0…100, ou nil si inconnu
    let pct: Double?
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let p = min(max((pct ?? 0) / 100, 0), 1)
            let fill = max(height, w * p)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                if pct != nil {
                    Capsule()
                        .fill(PulseStyle.limitGradient)
                        .frame(width: w)
                        .mask(alignment: .leading) { Capsule().frame(width: fill) }
                    Circle()
                        .fill(Color.white)
                        .frame(width: height - 4, height: height - 4)
                        .shadow(color: PulseStyle.gauge(pct ?? 0).opacity(0.9), radius: 4)
                        .offset(x: fill - height + 2)
                }
            }
        }
        .frame(height: height)
    }
}

/// Anneau de progression (jauge 5 h dans l'app, Dynamic Island minimale).
struct RingGauge: View {
    let pct: Double?
    var lineWidth: CGFloat = 10

    var body: some View {
        let p = min(max((pct ?? 0) / 100, 0), 1)
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: lineWidth)
            if pct != nil {
                Circle()
                    .trim(from: 0, to: max(p, 0.005))
                    .stroke(
                        AngularGradient(
                            colors: [PulseStyle.good, PulseStyle.warn, PulseStyle.hot, PulseStyle.critical],
                            center: .center, startAngle: .degrees(0), endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

/// Pastille de statut : icône dans un cercle teinté.
struct StatusBadge: View {
    let status: String
    var size: CGFloat = 34

    var body: some View {
        let color = PulseStyle.color(for: status)
        Image(systemName: PulseStyle.symbol(for: status))
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: Circle())
    }
}
