import Foundation
import Testing
@testable import DaladaCore

@Suite("Раздел «Фото» в профиле")
struct MyPhotosTests {
    private func photo(_ n: Int, _ date: String) -> MyPhoto {
        let formatter = ISO8601DateFormatter()
        return MyPhoto(
            id: UUID(uuidString: "EEEEEEEE-0000-0000-0000-00000000000\(n)")!,
            path: "a/\(n).jpg", thumbnailPath: "a/\(n)_thumb.jpg", width: 1600, height: 1200,
            createdAt: formatter.date(from: date)!, checkinID: nil, catchID: nil, reviewID: nil, placeID: nil, placeName: nil
        )
    }

    @Test func decodesRows() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([MyPhoto].self, from: Data("""
        [{"id": "eeeeeeee-0000-0000-0000-000000000004", "path": "a/4.jpg", "thumb_path": "a/4_thumb.jpg",
          "width": 1600, "height": 1200, "created_at": "2026-09-28T10:00:00Z",
          "checkin_id": null, "catch_id": null, "review_id": "aaaaaaaa-0000-0000-0000-000000000001",
          "place_id": "aaaaaaaa-0000-0000-0000-000000000002", "place_name": "Залив"}]
        """.utf8))
        #expect(rows.first?.reviewID != nil)
        #expect(rows.first?.placeName == "Залив")
        #expect(rows.first?.reportMedia.thumbnailPath == "a/4_thumb.jpg")
    }

    @Test func groupsByMonthNewestFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
        let photos = [photo(3, "2026-10-02T10:00:00Z"), photo(2, "2026-09-30T10:00:00Z"), photo(1, "2026-09-01T10:00:00Z")]
        let months = PhotoMonth.group(photos, calendar: calendar)
        #expect(months.map { $0.photos.count } == [1, 2])
        #expect(months.first?.photos.first?.id == photos[0].id)
    }
}
