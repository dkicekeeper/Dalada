import Testing
@testable import DaladaCore

@Suite("Упоминания в обсуждениях")
struct MentionsTests {
    @Test func findsMentionsLikeTheDatabase() {
        #expect(Mentions.parts(in: "Спроси @ddd и @Bob.") == [
            .text("Спроси "),
            .mention("@ddd", username: "ddd"),
            .text(" и "),
            .mention("@Bob", username: "bob"),
            .text("."),
        ])
        #expect(Mentions.parts(in: "@aaa, посмотрите") == [
            .mention("@aaa", username: "aaa"),
            .text(", посмотрите"),
        ])
    }

    @Test func ignoresMailWordsAndShortNames() {
        for text in ["почта x@aaa.kz", "слово@ccc", "@ab — коротко", "@@aaa", "просто текст"] {
            #expect(Mentions.parts(in: text) == [.text(text)], "\(text)")
        }
    }

    @Test func emptyTextHasNoParts() {
        #expect(Mentions.parts(in: "").isEmpty)
    }
}
