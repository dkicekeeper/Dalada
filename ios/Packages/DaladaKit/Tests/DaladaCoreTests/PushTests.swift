import Foundation
import Testing
@testable import DaladaCore

@Suite("Пуши")
struct PushTests {
    @Test func tokenIsLowercaseHex() {
        #expect(PushToken.hex(Data([0x00, 0xAB, 0x0F, 0xFF])) == "00ab0fff")
    }

    @Test func threadLinkRoundTrips() throws {
        let id = try #require(UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000001"))
        let url = ThreadLink.url(threadID: id)
        #expect(url.absoluteString == "dalada://thread/dddddddd-0000-0000-0000-000000000001")
        #expect(ThreadLink.threadID(from: url) == id)
        #expect(ThreadLink.threadID(from: URL(string: "dalada://u/bob")!) == nil)
        #expect(ThreadLink.threadID(from: URL(string: "dalada://thread/not-a-uuid")!) == nil)
        #expect(InviteLink.username(from: url) == nil, "ссылка на обсуждение — не приглашение")
    }

    @Test func packingAndLiveLinks() throws {
        let id = try #require(UUID(uuidString: "ABABABAB-0000-0000-0000-000000000001"))
        let url = PackingLink.url(packingID: id)
        #expect(url.absoluteString == "dalada://packing/abababab-0000-0000-0000-000000000001")
        #expect(PackingLink.packingID(from: url) == id)
        #expect(PackingLink.packingID(from: LiveLink.url) == nil)
        #expect(LiveLink.matches(URL(string: "dalada://live")!))
        #expect(!LiveLink.matches(url))
        #expect(InviteLink.username(from: LiveLink.url) == nil, "«на выезде» — не приглашение")
    }

    @Test func tripInviteLinks() {
        let token = "0123456789abcdef0123456789abcdef"
        let url = TripInviteLink.url(token: token)
        #expect(url.absoluteString == "dalada://trip-invite/" + token)
        #expect(TripInviteLink.token(from: url) == token)
        #expect(TripInviteLink.token(from: URL(string: "dalada://trip-invite/short")!) == nil)
        #expect(TripInviteLink.token(from: URL(string: "dalada://trip/" + token)!) == nil)
        #expect(WebLink.tripInvite(token).absoluteString == "https://dkicekeeper.github.io/Dalada/s/?invite=" + token)
    }

    @Test func placeCommentsLink() throws {
        let url = try #require(URL(string: "dalada://comments/place/aaaaaaaa-0000-0000-0000-000000000001"))
        #expect(CommentsLink.key(from: url)?.kind == .place)
    }
}
