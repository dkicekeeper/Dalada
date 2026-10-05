import Foundation

// MARK: - Смотритель и рекорды места

/// Смотритель места (RPC `place_steward`): больше всего публичных подтверждённых отчётов за 60 дней.
public struct PlaceSteward: Codable, Equatable, Hashable, Sendable {
    public let userID: UUID
    public let username: String?
    public let displayName: String?
    public let avatarPath: String?
    /// Отчётов за 60 дней.
    public let checkins: Int
    /// Первый из них.
    public let since: Date

    public init(userID: UUID, username: String?, displayName: String?, avatarPath: String?, checkins: Int, since: Date) {
        self.userID = userID
        self.username = username
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.checkins = checkins
        self.since = since
    }

    public var name: String? {
        displayName ?? username.map { "@" + $0 }
    }

    /// Окно, за которое считаются отчёты (как `private.steward_window` на сервере).
    public static let windowDays = 60

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case checkins
        case since
    }
}

/// Рекорд места (RPC `place_records`): самый тяжёлый улов вида с фото.
public struct PlaceRecord: Codable, Identifiable, Hashable, Sendable {
    public let speciesID: String
    public let weightGrams: Int
    public let lengthMillimeters: Int?
    public let caughtAt: Date
    public let catchID: UUID
    public let authorID: UUID
    public let authorUsername: String?
    public let authorDisplayName: String?
    public let photoPath: String
    public let photoThumbPath: String

    public var id: String { speciesID }

    public var authorName: String? {
        authorDisplayName ?? authorUsername.map { "@" + $0 }
    }

    public init(
        speciesID: String,
        weightGrams: Int,
        lengthMillimeters: Int?,
        caughtAt: Date,
        catchID: UUID,
        authorID: UUID,
        authorUsername: String?,
        authorDisplayName: String?,
        photoPath: String,
        photoThumbPath: String
    ) {
        self.speciesID = speciesID
        self.weightGrams = weightGrams
        self.lengthMillimeters = lengthMillimeters
        self.caughtAt = caughtAt
        self.catchID = catchID
        self.authorID = authorID
        self.authorUsername = authorUsername
        self.authorDisplayName = authorDisplayName
        self.photoPath = photoPath
        self.photoThumbPath = photoThumbPath
    }

    /// Самые тяжёлые — первыми.
    public static func sorted(_ records: [PlaceRecord]) -> [PlaceRecord] {
        records.sorted { ($0.weightGrams, $1.caughtAt) > ($1.weightGrams, $0.caughtAt) }
    }

    enum CodingKeys: String, CodingKey {
        case speciesID = "species_id"
        case weightGrams = "weight_g"
        case lengthMillimeters = "length_mm"
        case caughtAt = "caught_at"
        case catchID = "catch_id"
        case authorID = "author_id"
        case authorUsername = "author_username"
        case authorDisplayName = "author_display_name"
        case photoPath = "photo_path"
        case photoThumbPath = "photo_thumb_path"
    }
}
