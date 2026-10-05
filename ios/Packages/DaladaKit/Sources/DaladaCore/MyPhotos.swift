import Foundation

/// Своё фото для раздела «Фото» в профиле — строка `my_photos`: из отчёта, улова или отзыва.
public struct MyPhoto: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let path: String
    public let thumbnailPath: String
    public let width: Int?
    public let height: Int?
    public let createdAt: Date
    public let checkinID: UUID?
    public let catchID: UUID?
    public let reviewID: UUID?
    public let placeID: UUID?
    /// Пусто — место удалено или больше не видно.
    public let placeName: String?

    public init(
        id: UUID, path: String, thumbnailPath: String, width: Int?, height: Int?, createdAt: Date,
        checkinID: UUID?, catchID: UUID?, reviewID: UUID?, placeID: UUID?, placeName: String?
    ) {
        self.id = id
        self.path = path
        self.thumbnailPath = thumbnailPath
        self.width = width
        self.height = height
        self.createdAt = createdAt
        self.checkinID = checkinID
        self.catchID = catchID
        self.reviewID = reviewID
        self.placeID = placeID
        self.placeName = placeName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case thumbnailPath = "thumb_path"
        case width
        case height
        case createdAt = "created_at"
        case checkinID = "checkin_id"
        case catchID = "catch_id"
        case reviewID = "review_id"
        case placeID = "place_id"
        case placeName = "place_name"
    }

    /// Для просмотра на весь экран (тот же вид, что у фото отчёта).
    public var reportMedia: ReportMedia {
        ReportMedia(id: id, catchID: catchID, path: path, thumbnailPath: thumbnailPath, width: width, height: height)
    }
}

/// Фото по месяцам — для «Все фото»: новые месяцы сверху, внутри — в исходном порядке.
public struct PhotoMonth: Identifiable, Hashable, Sendable {
    /// Первое число месяца.
    public let id: Date
    public let photos: [MyPhoto]

    public static func group(_ photos: [MyPhoto], calendar: Calendar = .current) -> [PhotoMonth] {
        var months: [PhotoMonth] = []
        for photo in photos {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: photo.createdAt)) ?? photo.createdAt
            if let last = months.last, last.id == start {
                months[months.count - 1] = PhotoMonth(id: start, photos: last.photos + [photo])
            } else {
                months.append(PhotoMonth(id: start, photos: [photo]))
            }
        }
        return months
    }
}
