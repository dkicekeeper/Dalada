import Foundation
import Testing
@testable import DaladaCore

@Suite("Серии")
struct StreakTests {
    @Test func decodesStreak() throws {
        let rows = try JSONDecoder().decode([Streak].self, from: Data("""
        [{"current_weeks": 5, "best_weeks": 9, "this_week_done": false, "freeze_reason": "ban"}]
        """.utf8))
        #expect(rows.first == Streak(currentWeeks: 5, bestWeeks: 9, thisWeekDone: false, freeze: .ban))
    }

    @Test func unknownFreezeIsIgnored() throws {
        let streak = try JSONDecoder().decode(Streak.self, from: Data("""
        {"current_weeks": 1, "best_weeks": 1, "this_week_done": false, "freeze_reason": "holiday"}
        """.utf8))
        #expect(streak.freeze == nil)
    }

    @Test func hints() {
        #expect(Streak(currentWeeks: 3, bestWeeks: 3, thisWeekDone: true, freeze: .winter).hintKey == "streak.hint.done")
        #expect(Streak(currentWeeks: 3, bestWeeks: 3, thisWeekDone: false, freeze: .winter).hintKey == "streak.hint.winter")
        #expect(Streak(currentWeeks: 3, bestWeeks: 3, thisWeekDone: false).hintKey == "streak.hint.keep")
        #expect(Streak(currentWeeks: 0, bestWeeks: 3, thisWeekDone: false).hintKey == "streak.hint.start")
    }
}
