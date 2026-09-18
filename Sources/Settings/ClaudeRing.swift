import Foundation

/// What Claude's big ring reads, as one choice in Settings.
///
/// The weekly ring and the daily pace both re-lead the same ring, so they are
/// offered as one picker rather than two switches that could both be on.
/// `Preferences.claudeRing` maps it onto the two stored keys, which keeps the
/// daily pace under the key existing installs already have.
enum ClaudeRing: String, CaseIterable, Identifiable {
    case session
    case weekly
    case dailyPace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .session:   return L10n.t("Session")
        case .weekly:    return L10n.t("Weekly")
        case .dailyPace: return L10n.t("Daily pace")
        }
    }

    var explanation: String {
        switch self {
        case .session:
            return L10n.t("Claude's main ring shows the current session, as Claude Code's own /usage does. The weekly limit stays in the card and on the thin ring.")
        case .weekly:
            return L10n.t("Claude's main ring shows the weekly limit instead of the session. The session moves to the thin ring and the card; threshold alerts follow the weekly ring.")
        case .dailyPace:
            // The wording the daily-pace switch always had, so its translations carry over.
            return L10n.t("Claude's main ring shows today's share of the weekly limit \u{2014} a seventh a day, counted from the weekly reset \u{2014} instead of the session. The session moves to the thin ring and the card; alerts follow the daily ring.")
        }
    }
}
