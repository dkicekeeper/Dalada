import Foundation
import Testing
@testable import DaladaCore

@Suite("Place stewards")
struct PlaceStewardsTests {
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test func decodesStewardAndRecords() throws {
        let steward = """
        [{"user_id": "11111111-1111-1111-1111-111111111111", "username": "ivan", "display_name": null,
          "avatar_path": null, "checkins": 8, "since": "2026-08-20T05:00:00Z"}]
        """
        let decoded = try decoder.decode([PlaceSteward].self, from: Data(steward.utf8)).first
        #expect(decoded?.checkins == 8)
        #expect(decoded?.name == "@ivan")

        let records = """
        [{"species_id": "perch", "weight_g": 300, "length_mm": null, "caught_at": "2026-10-01T05:00:00Z",
          "catch_id": "dddddddd-0000-0000-0000-000000000003", "author_id": "22222222-2222-2222-2222-222222222222",
          "author_username": "olga", "author_display_name": "Ольга", "photo_path": "u/m.jpg", "photo_thumb_path": "u/m_thumb.jpg"},
         {"species_id": "pike", "weight_g": 2000, "length_mm": 650, "caught_at": "2026-10-02T05:00:00Z",
          "catch_id": "dddddddd-0000-0000-0000-000000000001", "author_id": "11111111-1111-1111-1111-111111111111",
          "author_username": "ivan", "author_display_name": null, "photo_path": "u/p.jpg", "photo_thumb_path": "u/p_thumb.jpg"}]
        """
        let rows = PlaceRecord.sorted(try decoder.decode([PlaceRecord].self, from: Data(records.utf8)))
        #expect(rows.map(\.speciesID) == ["pike", "perch"])
        #expect(rows.last?.authorName == "Ольга")
    }
}
