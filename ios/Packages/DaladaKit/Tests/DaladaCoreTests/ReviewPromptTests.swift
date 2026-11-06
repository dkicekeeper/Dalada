import Foundation
import Testing
@testable import DaladaCore

@Suite("Запрос оценки")
struct ReviewPromptTests {
    private let day: TimeInterval = 24 * 60 * 60
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(moments: Int, daysAgo: Double) -> ReviewPromptPolicy.State {
        ReviewPromptPolicy.State(firstSeen: start.addingTimeInterval(-daysAgo * day), moments: moments)
    }

    @Test func asksAfterThreeMomentsAndThreeDays() {
        #expect(ReviewPromptPolicy.shouldPrompt(state(moments: 3, daysAgo: 3), now: start, version: "1.0.1"))
        #expect(!ReviewPromptPolicy.shouldPrompt(state(moments: 2, daysAgo: 30), now: start, version: "1.0.1"),
                "мало удачных моментов")
        #expect(!ReviewPromptPolicy.shouldPrompt(state(moments: 10, daysAgo: 2.9), now: start, version: "1.0.1"),
                "слишком рано после установки")
        #expect(!ReviewPromptPolicy.shouldPrompt(ReviewPromptPolicy.State(moments: 5), now: start, version: "1.0.1"),
                "первый запуск неизвестен")
    }

    @Test func countsMomentsAndRemembersFirstLaunch() {
        var current = ReviewPromptPolicy.State()
        ReviewPromptPolicy.noteLaunch(&current, now: start)
        ReviewPromptPolicy.noteLaunch(&current, now: start.addingTimeInterval(day))
        #expect(current.firstSeen == start, "первый запуск не переписывается")
        ReviewPromptPolicy.noteMoment(&current, now: start)
        ReviewPromptPolicy.noteMoment(&current, now: start)
        #expect(current.moments == 2)

        var fresh = ReviewPromptPolicy.State()
        ReviewPromptPolicy.noteMoment(&fresh, now: start)
        #expect(fresh.firstSeen == start, "момент без запуска тоже запоминает первый день")
    }

    @Test func onceAVersionAndNotTooOften() {
        var current = state(moments: 3, daysAgo: 10)
        ReviewPromptPolicy.notePrompted(&current, now: start, version: "1.0.1")
        #expect(current.moments == 0)

        current.moments = 5
        #expect(!ReviewPromptPolicy.shouldPrompt(current, now: start.addingTimeInterval(200 * day), version: "1.0.1"),
                "в той же версии не спрашиваем")
        #expect(!ReviewPromptPolicy.shouldPrompt(current, now: start.addingTimeInterval(30 * day), version: "1.0.2"),
                "новая версия, но прошло меньше 120 дней")
        #expect(ReviewPromptPolicy.shouldPrompt(current, now: start.addingTimeInterval(121 * day), version: "1.0.2"))
    }

    @Test func stateSurvivesJSON() throws {
        let original = ReviewPromptPolicy.State(firstSeen: start, moments: 2, lastPromptVersion: "1.0.1", lastPromptAt: start)
        let decoded = try JSONDecoder().decode(ReviewPromptPolicy.State.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
