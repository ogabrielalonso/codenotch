import Foundation

/// Claude's weekly window as the big ring, with the session on the thin one.
///
/// Claude's snapshot leads with the five-hour session so the ring agrees with
/// Claude Code's own `/usage`. Someone who budgets the week wants the ring to
/// read the limit that can stop work for days instead, so this swaps the two
/// declared roles. Like `DailyPace`, it is laid over the store's snapshots on
/// the way out: the store keeps what the vendor said, and flipping the setting
/// redraws without a fetch.
enum ClaudeWeeklyHeadline {
    /// Only a Claude snapshot still led by the vendor's session is changed.
    /// One with no weekly reading keeps its session ring rather than showing
    /// nothing, and one the daily pace already re-led is left to that choice.
    static func apply(to snapshot: ProviderSnapshot) -> ProviderSnapshot {
        guard ClaudeProfile.isClaude(providerID: snapshot.providerID),
              snapshot.headlineID == "session",
              snapshot.windows.contains(where: { $0.id == "weekly_all" }) else { return snapshot }
        var swapped = snapshot
        swapped.headlineID = "weekly_all"
        swapped.weeklyID = snapshot.windows.contains { $0.id == "session" } ? "session" : nil
        return swapped
    }

    static func apply(to snapshots: [ProviderSnapshot], enabled: Bool) -> [ProviderSnapshot] {
        guard enabled else { return snapshots }
        return snapshots.map(apply(to:))
    }
}
