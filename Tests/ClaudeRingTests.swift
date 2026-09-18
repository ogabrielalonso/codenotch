import Combine
import XCTest
@testable import Codenotch

final class ClaudeWeeklyHeadlineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var session: LimitWindow {
        LimitWindow(id: "session", label: "Current session", usedFraction: 0.42,
                    resetsAt: now.addingTimeInterval(3_600), duration: 5 * 3600)
    }

    private var weekly: LimitWindow {
        LimitWindow(id: "weekly_all", label: "All models", usedFraction: 0.30,
                    resetsAt: now.addingTimeInterval(3 * 86_400), duration: 7 * 86_400)
    }

    private func claude(id: String = "claude", windows: [LimitWindow]) -> ProviderSnapshot {
        ProviderSnapshot(id: id, displayName: "Claude", glyph: .claude, fidelity: .official,
                         status: .ok, windows: windows, headlineID: "session", weeklyID: "weekly_all")
    }

    func testWeeklyLeadsAndTheSessionTakesTheThinRing() throws {
        let swapped = ClaudeWeeklyHeadline.apply(to: claude(windows: [session, weekly]))
        XCTAssertEqual(swapped.headlineID, "weekly_all")
        XCTAssertEqual(try XCTUnwrap(swapped.usedFraction), 0.30, accuracy: 1e-9)
        XCTAssertEqual(swapped.weeklyID, "session")
        XCTAssertEqual(swapped.weeklyFraction, 0.42)
        XCTAssertEqual(swapped.windows.map(\.id), ["session", "weekly_all"], "the card keeps both windows")
    }

    func testAppliesToEveryClaudeProfileAndNothingElse() {
        let work = ClaudeWeeklyHeadline.apply(to: claude(id: "claude-work", windows: [session, weekly]))
        XCTAssertEqual(work.headlineID, "weekly_all")

        let codex = ProviderSnapshot(id: "codex", displayName: "Codex", glyph: .openai, fidelity: .official,
                                     status: .ok, windows: [session, weekly], headlineID: "session",
                                     weeklyID: "weekly_all")
        XCTAssertEqual(ClaudeWeeklyHeadline.apply(to: codex), codex)
    }

    func testKeepsTheSessionRingWhenThereIsNoWeeklyReading() {
        let original = claude(windows: [session])
        XCTAssertEqual(ClaudeWeeklyHeadline.apply(to: original), original)
    }

    func testWithoutASessionTheThinRingIsLeftEmpty() {
        let swapped = ClaudeWeeklyHeadline.apply(to: claude(windows: [weekly]))
        XCTAssertEqual(swapped.headlineID, "weekly_all")
        XCTAssertNil(swapped.weeklyID)
    }

    func testLeavesADailyPaceSnapshotToThatChoice() {
        let paced = DailyPace.apply(to: claude(windows: [session, weekly]), now: now)
        XCTAssertEqual(ClaudeWeeklyHeadline.apply(to: paced), paced)
    }

    func testDoesNotFlipBackOnARepeatPass() {
        let once = ClaudeWeeklyHeadline.apply(to: claude(windows: [session, weekly]))
        XCTAssertEqual(ClaudeWeeklyHeadline.apply(to: once), once)
    }

    func testDisabledIsAPassThrough() {
        let snapshots = [claude(windows: [session, weekly])]
        XCTAssertEqual(ClaudeWeeklyHeadline.apply(to: snapshots, enabled: false), snapshots)
        XCTAssertEqual(ClaudeWeeklyHeadline.apply(to: snapshots, enabled: true).first?.headlineID, "weekly_all")
    }
}

@MainActor
final class ClaudeRingPreferenceTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "ClaudeRingPreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    func testDefaultsToTheSessionAndSurvivesARelaunch() throws {
        try withDefaults { defaults in
            XCTAssertEqual(Preferences(defaults: defaults).claudeRing, .session)
            Preferences(defaults: defaults).claudeRing = .weekly
            XCTAssertEqual(Preferences(defaults: defaults).claudeRing, .weekly)
        }
    }

    func testEachChoiceStoresOnlyItsOwnFlag() throws {
        try withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.claudeRing = .weekly
            preferences.claudeRing = .dailyPace
            XCTAssertTrue(defaults.bool(forKey: "claudeDailyPaceRing"))
            XCTAssertFalse(defaults.bool(forKey: "claudeWeeklyHeadline"))

            preferences.claudeRing = .session
            XCTAssertFalse(defaults.bool(forKey: "claudeDailyPaceRing"))
            XCTAssertFalse(defaults.bool(forKey: "claudeWeeklyHeadline"))
        }
    }

    func testAnInstallThatAlreadyUsedTheDailyPaceKeepsIt() throws {
        try withDefaults { defaults in
            defaults.set(true, forKey: "claudeDailyPaceRing")
            XCTAssertEqual(Preferences(defaults: defaults).claudeRing, .dailyPace)
        }
    }

    /// Going from the daily pace to the weekly ring must not publish the
    /// session on the way: the threshold notifier would read the drop and then
    /// alert on the weekly reading as if it had just been crossed.
    func testSwitchingPublishesTheChoiceAloneWithNothingInBetween() throws {
        try withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.claudeRing = .dailyPace
            var published: [ClaudeRing] = []
            let watching = preferences.$claudeRing.dropFirst().sink { published.append($0) }
            preferences.claudeRing = .weekly
            watching.cancel()
            XCTAssertEqual(published, [.weekly])
        }
    }
}
