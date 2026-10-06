import Foundation
import Testing
@testable import DaladaCore

@Suite("Фото на карте")
struct PhotoPointTests {
    @Test func decodesAndRoundTrips() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let points = try decoder.decode([MyPhotoPoint].self, from: Data("""
        [{"id": "eeeeeeee-0000-0000-0000-000000000001", "path": "u/e.jpg", "thumb_path": "u/e_thumb.jpg",
          "width": 1600, "height": 1200, "created_at": "2026-10-06T10:00:00Z",
          "checkin_id": null, "catch_id": null, "review_id": null, "place_id": null, "place_name": "Залив",
          "lon": 77.001, "lat": 43.901}]
        """.utf8))
        let point = try #require(points.first)
        #expect(point.coordinate == GeoPoint(latitude: 43.901, longitude: 77.001))
        #expect(point.photo.placeName == "Залив")
        let again = try decoder.decode(MyPhotoPoint.self, from: encoder.encode(point))
        #expect(again == point)
    }
}
