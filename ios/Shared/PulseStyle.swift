import SwiftUI
import UIKit

/// Identité visuelle commune à l'app, au widget et à la Live Activity.
/// Toutes les couleurs suivent le thème clair / sombre du téléphone ; la Live Activity force le sombre.
enum PulseStyle {
    // MARK: Couleurs (inspirées de l'app Claude : ivoire chaud, gris sable, orange pêche)

    /// Claude's Peach #DE7356
    static let peach = Color(red: 222 / 255, green: 115 / 255, blue: 86 / 255)
    /// Crail #C15F3C
    static let crail = Color(red: 193 / 255, green: 95 / 255, blue: 60 / 255)

    /// Accent : Crail sur fond clair (plus lisible), pêche sur fond sombre.
    static let accent = dynamic(0xC15F3C, 0xDE7356)
    static let accentSoft = dynamic(0xDE7356, 0xE8927A)

    /// Fond de l'écran (ivoire / anthracite chaud)
    static let background = dynamic(0xF8F7F3, 0x1F1E1C)
    /// Groupes de lignes et cartes (gris sable)
    static let card = dynamic(0xEFEDE7, 0x2B2A27)
    static let cardRaised = dynamic(0xE5E2DA, 0x37352F)
    /// Boutons ronds flottants
    static let floating = dynamic(0xFFFFFF, 0x34322E)
    static let stroke = dynamic(0x000000, 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.07)
    static let separator = dynamic(0x000000, 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.08)
    static let track = dynamic(0x000000, 0xFFFFFF, lightAlpha: 0.09, darkAlpha: 0.14)

    static let textPrimary = dynamic(0x1F1E1C, 0xF4F2EC)
    static let textSecondary = dynamic(0x6E6A62, 0xB3AEA4)
    static let textTertiary = dynamic(0x9D988E, 0x7E796F)

    static let good = dynamic(0x2E9E5B, 0x5CD187)
    static let warn = dynamic(0xC98A10, 0xFAC24A)
    static let hot = dynamic(0xE0702F, 0xF5854A)
    static let critical = dynamic(0xD63B3B, 0xF0544F)
    static let info = dynamic(0x3D6FE0, 0x6B9EFF)

    /// Dégradé des limites : vert → jaune → orange → rouge, sur toute la largeur.
    static let limitGradient = LinearGradient(colors: [good, warn, hot, critical], startPoint: .leading, endPoint: .trailing)

    static func color(for status: String) -> Color {
        switch status {
        case "running": return accent
        case "waiting": return warn
        case "background": return info
        case "done": return good
        case "error": return critical
        default: return textTertiary
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

    private static let fr = Locale(identifier: "fr_FR")

    /// « 14:00 » aujourd'hui, « mer. 14:00 » au-delà.
    static func resetTime(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute().locale(fr))
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(fr))
    }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(fr))
    }

    /// « 1 234,56 $ »
    static func dollars(_ usd: Double, decimals: Int = 2) -> String {
        usd.formatted(.number.precision(.fractionLength(decimals)).locale(fr)) + " $"
    }

    /// « 12,4 M », « 850 k », « 512 »
    static func tokens(_ n: Int) -> String {
        let v = Double(n)
        switch v {
        case 1_000_000_000...: return (v / 1e9).formatted(.number.precision(.fractionLength(1)).locale(fr)) + " Md"
        case 1_000_000...: return (v / 1e6).formatted(.number.precision(.fractionLength(1)).locale(fr)) + " M"
        case 10_000...: return (v / 1e3).formatted(.number.precision(.fractionLength(0)).locale(fr)) + " k"
        default: return n.formatted(.number.locale(fr))
        }
    }

    /// « 34 s », « 2 min », « 1 h 05 »
    static func shortDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(max(seconds, 0)) s" }
        let min = seconds / 60
        if min < 60 { return "\(min) min" }
        return "\(min / 60) h \(String(format: "%02d", min % 60))"
    }

    /// « 7 sept. »
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(fr))
    }

    /// « ≈ 6 min », « ≈ 1 h 20 », « < 1 min »
    static func remaining(_ seconds: Int) -> String {
        let min = Int((Double(seconds) / 60).rounded())
        if min < 1 { return "< 1 min" }
        if min < 60 { return "≈ \(min) min" }
        let h = min / 60, m = min % 60
        return m == 0 ? "≈ \(h) h" : "≈ \(h) h \(String(format: "%02d", m))"
    }

    // MARK: Utilitaire

    private static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Composants partagés

/// Barre de limite pleine, en dégradé, avec un curseur au bout (app et widget).
struct LimitBar: View {
    /// 0…100, ou nil si inconnu
    let pct: Double?
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let p = min(max((pct ?? 0) / 100, 0), 1)
            let fill = max(height, w * p)
            ZStack(alignment: .leading) {
                Capsule().fill(PulseStyle.track)
                if pct != nil {
                    Capsule()
                        .fill(PulseStyle.limitGradient)
                        .frame(width: w)
                        .mask(alignment: .leading) { Capsule().frame(width: fill) }
                }
            }
        }
        .frame(height: height)
    }
}

/// Piste façon « course en approche » : trait plein jusqu'au curseur, pointillés ensuite,
/// repère au bout. Le curseur porte l'icône de l'app.
struct LimitTrack: View {
    let pct: Double?
    var color: Color = PulseStyle.accent

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let knob: CGFloat = 26
            let p = min(max((pct ?? 0) / 100, 0), 1)
            let x = knob / 2 + (w - knob) * p
            ZStack(alignment: .leading) {
                // Reste à consommer : pointillés
                Path { path in
                    path.move(to: CGPoint(x: x, y: knob / 2))
                    path.addLine(to: CGPoint(x: w - 6, y: knob / 2))
                }
                .stroke(PulseStyle.track, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [6, 7]))

                // Déjà consommé : trait plein
                Capsule()
                    .fill(color)
                    .frame(width: max(x, 4), height: 4)
                    .offset(y: 0)

                // Repère de fin (100 %)
                Circle()
                    .strokeBorder(PulseStyle.track, lineWidth: 3)
                    .frame(width: 12, height: 12)
                    .offset(x: w - 12)

                // Curseur
                ZStack {
                    Circle().fill(PulseStyle.card)
                    Circle().strokeBorder(color, lineWidth: 2.5)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                }
                .frame(width: knob, height: knob)
                .offset(x: x - knob / 2)
                .opacity(pct == nil ? 0 : 1)
            }
            .frame(height: knob)
        }
        .frame(height: 26)
    }
}

/// Barre segmentée façon suivi de commande : un segment par étape.
struct SegmentedBar: View {
    let done: Int
    let total: Int
    var color: Color = PulseStyle.accent
    var height: CGFloat = 5

    var body: some View {
        let segments = min(max(total, 1), 12)
        // Au-delà de 12 étapes, chaque segment représente plusieurs étapes.
        let filled = total > 0 ? Int((Double(done) / Double(total) * Double(segments)).rounded(.down)) : 0
        HStack(spacing: 5) {
            ForEach(0..<segments, id: \.self) { i in
                Capsule()
                    .fill(i < filled ? color : (i == filled && done < total ? color.opacity(0.45) : PulseStyle.track))
                    .frame(height: height)
            }
        }
    }
}

/// Anneau de progression (jauge 5 h, Dynamic Island minimale).
struct RingGauge: View {
    let pct: Double?
    var lineWidth: CGFloat = 10

    var body: some View {
        let p = min(max((pct ?? 0) / 100, 0), 1)
        ZStack {
            Circle().stroke(PulseStyle.track, lineWidth: lineWidth)
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

// MARK: - Retours haptiques

/// Règles communes : léger pour naviguer, net pour une action, notification pour un événement.
enum PulseHaptics {
    /// Évolution des sessions vue depuis l'app ouverte : validation demandée → avertissement,
    /// tâche terminée → succès, erreur → erreur. Rien pour le reste.
    static func sessions(old: [String: String], new: [String: String]) -> SensoryFeedback? {
        // Premier chargement : rien ne « vient » de changer.
        guard !old.isEmpty else { return nil }
        var feedback: SensoryFeedback?
        for (sid, status) in new where old[sid] != status {
            switch status {
            case "error": return .error
            case "waiting": feedback = .warning
            case "done" where old[sid] != nil: if feedback == nil { feedback = .success }
            default: break
            }
        }
        return feedback
    }

    /// Statut qui vient de changer dans la vue détaillée d'une session.
    static func status(_ status: String) -> SensoryFeedback? {
        switch status {
        case "waiting": return .warning
        case "done": return .success
        case "error": return .error
        default: return nil
        }
    }

    /// Palier de limite (50 %, 75 %, 90 %) ; -1 tant que la limite est inconnue.
    static func level(_ pct: Double?) -> Int {
        guard let pct else { return -1 }
        switch pct {
        case ..<50: return 0
        case ..<75: return 1
        case ..<90: return 2
        default: return 3
        }
    }
}
