import Foundation
import Testing
@testable import DaladaCore

@Suite("Участники поездки")
struct TripParticipantsTests {
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func summary(_ id: String, startedAt: TimeInterval) -> TripSummary {
        TripSummary(
            id: UUID(uuidString: id)!,
            activity: .fishing,
            title: id,
            note: nil,
            startedAt: Date(timeIntervalSince1970: startedAt),
            endedAt: Date(timeIntervalSince1970: startedAt + 3600),
            movingSeconds: 0,
            distanceM: 0,
            elevationGainM: 0,
            maxSpeedMps: nil,
            visibility: .private
        )
    }

    @Test func decodesParticipantsAndFindsMe() throws {
        let rows = try decoder.decode([TripParticipant].self, from: Data("""
        [{"user_id": "22222222-2222-2222-2222-222222222222", "username": "friend_f", "display_name": null,
          "avatar_path": null, "status": "accepted", "is_me": false},
         {"user_id": "55555555-5555-5555-5555-555555555555", "username": "me", "display_name": "Я",
          "avatar_path": null, "status": "pending", "is_me": true}]
        """.utf8))
        #expect(rows.map(\.status) == [.accepted, .pending])
        #expect(TripParticipants.mine(in: rows)?.username == "me")
    }

    @Test func decodesInvitationWithOwner() throws {
        let rows = try decoder.decode([TripInvitation].self, from: Data("""
        [{"trip_id": "99999999-0000-0000-0000-000000000001", "title": "Рыбалка втроём", "activity": "fishing",
          "started_at": "2026-10-04T05:00:00Z", "ended_at": "2026-10-04T08:00:00Z",
          "owner_id": "11111111-1111-1111-1111-111111111111", "owner_username": "author",
          "owner_display_name": null, "owner_avatar_path": null, "tagged_at": "2026-10-04T09:00:00Z"}]
        """.utf8))
        #expect(rows.first?.owner.username == "author")
        #expect(rows.first?.title == "Рыбалка втроём")
        let copy = try JSONDecoder().decode([TripInvitation].self, from: JSONEncoder().encode(rows))
        #expect(copy == rows)
    }

    @Test func decodesJoinedTripWithHost() throws {
        let rows = try decoder.decode([JoinedTrip].self, from: Data("""
        [{"id": "99999999-0000-0000-0000-000000000001", "activity": "fishing", "title": "Рыбалка втроём",
          "note": null, "started_at": "2026-10-04T05:00:00Z", "ended_at": "2026-10-04T08:00:00Z",
          "moving_seconds": 600, "distance_m": 2000, "elevation_gain_m": 0, "max_speed_mps": null,
          "visibility": "private", "host_id": "11111111-1111-1111-1111-111111111111",
          "host_username": "author", "host_display_name": null, "host_avatar_path": null}]
        """.utf8))
        #expect(rows.first?.host.username == "author")
        #expect(rows.first?.summary.distanceM == 2000)
        // Сохранённая копия «Моих поездок» читается обратно.
        let copy = try JSONDecoder().decode([JoinedTrip].self, from: JSONEncoder().encode(rows))
        #expect(copy == rows)
    }

    @Test func mergesOwnAndJoinedNewestFirst() {
        let own = [summary("00000000-0000-0000-0000-000000000001", startedAt: 100)]
        let host = TripOwner(id: UUID(), username: "author", displayName: nil)
        let joined = [
            JoinedTrip(summary: summary("00000000-0000-0000-0000-000000000002", startedAt: 200), host: host),
            // Своя поездка, пришедшая и в чужих, — один раз.
            JoinedTrip(summary: summary("00000000-0000-0000-0000-000000000001", startedAt: 100), host: host),
        ]
        let entries = TripListEntry.merged(own: own, joined: joined)
        #expect(entries.map(\.summary.title) == ["00000000-0000-0000-0000-000000000002", "00000000-0000-0000-0000-000000000001"])
        #expect(entries[0].host?.username == "author")
        #expect(entries[1].host == nil)
    }
}
