import Foundation
import Testing
@testable import DaladaCore

@Suite("Слой «Мои треки»")
struct MyTracksTests {
    private let rows = """
    [{"trip_id": "77777777-0000-0000-0000-000000000002", "activity": "hiking", "started_at": "2026-09-20T05:00:00Z",
      "track": {"type": "LineString", "coordinates": [[76.9, 43.1], [76.91, 43.11]]}},
     {"trip_id": "77777777-0000-0000-0000-000000000001", "activity": "kayaking", "started_at": "2026-09-01T05:00:00Z",
      "track": {"type": "LineString", "coordinates": [[77.0, 43.9], [77.01, 43.905], [77.02, 43.91]]}},
     {"trip_id": "77777777-0000-0000-0000-000000000003", "activity": "fishing", "started_at": "2026-08-01T05:00:00Z",
      "track": {"type": "LineString", "coordinates": [[77.0, 43.9]]}}]
    """

    private func decode() throws -> [TrackLine] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TrackLine].self, from: Data(rows.utf8))
    }

    @Test func decodesTracksAndUnknownActivity() throws {
        let lines = try decode()
        #expect(lines.count == 3)
        #expect(lines[0].activity == .hiking)
        #expect(lines[1].activity == .other)
        #expect(lines[1].segments == [[
            GeoPoint(latitude: 43.9, longitude: 77.0),
            GeoPoint(latitude: 43.905, longitude: 77.01),
            GeoPoint(latitude: 43.91, longitude: 77.02),
        ]])
        // Линию из одной точки не нарисовать.
        #expect(lines[2].segments.isEmpty)
        #expect(TrackLine.segments(lines).count == 2)
    }

    @Test func savedCopyReadsBack() throws {
        let lines = try decode()
        let copy = try JSONDecoder().decode([TrackLine].self, from: JSONEncoder().encode(lines))
        #expect(copy == lines)
    }
}
