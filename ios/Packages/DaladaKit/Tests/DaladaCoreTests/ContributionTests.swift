import Foundation
import Testing
@testable import DaladaCore

@Suite("Вклад и уровни")
struct ContributionTests {
    @Test func decodesContribution() throws {
        let rows = try JSONDecoder().decode([Contribution].self, from: Data("""
        [{"points": 120, "level": "knower", "next_level_points": 200, "places": 3, "photos": 4, "reports": 0,
          "reviews": 4, "edits": 0, "helpful": 0, "can_review": false, "review_queue": 0}]
        """.utf8))
        let contribution = try #require(rows.first)
        #expect(contribution.level == .knower)
        #expect(contribution.nextLevel == .expert)
        #expect(abs(contribution.progress - (70.0 / 150.0)) < 0.0001)
    }

    @Test func topLevelIsFull() {
        let keeper = Contribution(points: 900, level: .keeper, nextLevelPoints: nil)
        #expect(keeper.nextLevel == nil)
        #expect(keeper.progress == 1)
    }

    @Test func unknownLevelFallsBack() throws {
        let contribution = try JSONDecoder().decode(Contribution.self, from: Data("""
        {"points": 5000, "level": "legend", "next_level_points": null}
        """.utf8))
        #expect(contribution.level == .novice)
    }

    @Test func decodesReviewItem() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(SuggestionReviewItem.self, from: Data("""
        {"id": "11111111-1111-1111-1111-111111111111", "place_id": "aaaaaaaa-0000-0000-0000-000000000001",
         "place_name": "Залив", "place_type": "fishing_spot", "place_description": null,
         "changes": {"name": "Залив Тихий", "attributes": {"fish": ["pike"]}}, "note": "так называют",
         "author_username": "nnn", "created_at": "2026-10-06T10:00:00Z"}
        """.utf8))
        #expect(item.newName == "Залив Тихий")
        #expect(item.newType == nil)
        #expect(item.changesAttributes)
    }
}
