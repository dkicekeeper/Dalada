import Foundation
import Testing
@testable import DaladaCore

@Suite("Предложение поделиться после поездки")
struct SharePromptTests {
    private let day: TimeInterval = 24 * 60 * 60
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func offersFirstTimeAndThenEveryThreeDays() {
        var state = SharePromptPolicy.State()
        #expect(SharePromptPolicy.shouldOffer(state, now: start), "первая поездка — предлагаем")
        SharePromptPolicy.noteOffered(&state, now: start)
        #expect(!SharePromptPolicy.shouldOffer(state, now: start.addingTimeInterval(2.9 * day)), "не чаще раза в три дня")
        #expect(SharePromptPolicy.shouldOffer(state, now: start.addingTimeInterval(3 * day)))
    }

    @Test func stopsAfterThreeDeclinesInARow() {
        var state = SharePromptPolicy.State()
        for _ in 0..<2 { SharePromptPolicy.noteAnswer(&state, shared: false) }
        #expect(SharePromptPolicy.shouldOffer(state, now: start), "два отказа — ещё предлагаем")
        SharePromptPolicy.noteAnswer(&state, shared: false)
        #expect(!SharePromptPolicy.shouldOffer(state, now: start.addingTimeInterval(30 * day)), "три отказа подряд — хватит")
    }

    @Test func sharingResetsDeclines() {
        var state = SharePromptPolicy.State(declines: 2)
        SharePromptPolicy.noteAnswer(&state, shared: true)
        #expect(state.declines == 0)
        SharePromptPolicy.noteAnswer(&state, shared: false)
        SharePromptPolicy.noteAnswer(&state, shared: false)
        #expect(SharePromptPolicy.shouldOffer(state, now: start), "отказы считаются подряд")
    }
}
