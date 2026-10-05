import Foundation
import Testing
@testable import DaladaCore

@Suite("Live share")
struct LiveShareTests {
    private let start = Date(timeIntervalSince1970: 1_791_201_600)
    private let here = GeoPoint(latitude: 43.90, longitude: 77.05)

    @Test func sendsFirstPointRightAway() {
        #expect(LiveSharePolicy.shouldSend(lastPoint: nil, lastSentAt: nil, point: here, at: start))
    }

    @Test func notMoreOftenThanOncePerMinute() {
        let far = GeoPoint(latitude: 43.95, longitude: 77.05)
        #expect(!LiveSharePolicy.shouldSend(lastPoint: here, lastSentAt: start, point: far, at: start.addingTimeInterval(30)))
        #expect(LiveSharePolicy.shouldSend(lastPoint: here, lastSentAt: start, point: far, at: start.addingTimeInterval(61)))
    }

    @Test func standingStillSendsAHeartbeat() {
        let near = GeoPoint(latitude: 43.9005, longitude: 77.05) // ≈55 м
        #expect(!LiveSharePolicy.shouldSend(lastPoint: here, lastSentAt: start, point: near, at: start.addingTimeInterval(120)))
        #expect(LiveSharePolicy.shouldSend(lastPoint: here, lastSentAt: start, point: near, at: start.addingTimeInterval(300)))
    }

    @Test func decodesFriendLocation() throws {
        let json = """
        [{"owner_id": "22222222-2222-2222-2222-222222222222", "username": "ivan", "display_name": null,
          "avatar_path": null, "latitude": null, "longitude": null, "accuracy_m": null,
          "updated_at": "2026-10-05T12:00:00Z", "started_at": "2026-10-05T10:00:00Z",
          "expires_at": "2026-10-05T22:00:00Z", "in_privacy_zone": true}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([FriendLiveLocation].self, from: Data(json.utf8))
        #expect(rows.first?.coordinate == nil)
        #expect(rows.first?.inPrivacyZone == true)
        #expect(rows.first?.name == "@ivan")

        let mine = """
        [{"started_at": "2026-10-05T10:00:00Z", "expires_at": "2026-10-05T22:00:00Z", "updated_at": null,
          "viewer_ids": ["22222222-2222-2222-2222-222222222222"]}]
        """
        let share = try decoder.decode([MyLiveShare].self, from: Data(mine.utf8)).first
        #expect(share?.viewerIDs.count == 1)
        #expect(share?.isActive(at: start) == true)
    }
}
