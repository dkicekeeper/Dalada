import Foundation
import Testing
@testable import DaladaCore

@Suite("Настройки уведомлений")
struct NotificationSettingsTests {
    @Test func quietHoursAcrossMidnight() {
        let night = QuietHours(from: 22, to: 8)
        #expect(night.contains(hour: 22))
        #expect(night.contains(hour: 3))
        #expect(!night.contains(hour: 8))
        #expect(!night.contains(hour: 12))
    }

    @Test func quietHoursWithinDay() {
        let afternoon = QuietHours(from: 13, to: 15)
        #expect(afternoon.contains(hour: 13))
        #expect(afternoon.contains(hour: 14))
        #expect(!afternoon.contains(hour: 15))
        #expect(!afternoon.contains(hour: 2))
    }

    @Test func sameStartAndEndMeansNoQuietHours() {
        let none = QuietHours(from: 7, to: 7)
        #expect((0..<24).allSatisfy { !none.contains(hour: $0) })
    }

    @Test func clampsHours() {
        #expect(QuietHours(from: -1, to: 30) == QuietHours(from: 0, to: 23))
    }

    @Test func profileReadsSettings() throws {
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data("""
        {"id": "11111111-1111-1111-1111-111111111111", "language": "ru",
         "notify_replies": true, "notify_friend_requests": false, "notify_comments": true,
         "notify_friend_posts": false, "notify_bans": false, "notify_place_activity": true,
         "notify_trip_tags": false, "notify_reactions": false, "notify_live_share": false,
         "notify_steward": true, "notify_streak": false, "quiet_from": 23, "quiet_to": 7}
        """.utf8))
        #expect(profile.notificationSettings == NotificationSettings(
            friendRequests: false,
            friendPosts: false,
            bans: false,
            tripTags: false,
            reactions: false,
            liveShare: false,
            streak: false,
            quietHours: QuietHours(from: 23, to: 7)
        ))
    }

    @Test func oldProfileHasEverythingOn() throws {
        let old = try JSONDecoder().decode(UserProfile.self, from: Data("""
        {"id": "11111111-1111-1111-1111-111111111111", "language": "ru"}
        """.utf8))
        #expect(old.notificationSettings == NotificationSettings())
    }

    @Test func encodesNullQuietHours() throws {
        let data = try JSONEncoder().encode(NotificationSettings(comments: false))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["notify_comments"] as? Bool == false)
        #expect(json["notify_bans"] as? Bool == true)
        #expect(json["notify_trip_tags"] as? Bool == true)
        #expect(json["notify_reactions"] as? Bool == true)
        #expect(json["notify_live_share"] as? Bool == true)
        #expect(json["notify_steward"] as? Bool == true)
        #expect(json["notify_streak"] as? Bool == true)
        #expect(json["quiet_from"] is NSNull)
        #expect(json["quiet_to"] is NSNull)
        #expect(json.count == 13)
    }

    @Test func encodesQuietHours() throws {
        let data = try JSONEncoder().encode(NotificationSettings(quietHours: .default))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["quiet_from"] as? Int == 22)
        #expect(json["quiet_to"] as? Int == 8)
    }
}
