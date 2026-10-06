import Foundation

/// Уровень участника по очкам вклада: Новичок → Знаток (50) → Эксперт (200) → Хранитель (500).
/// С «Эксперта» можно разбирать чужие правки мест.
public enum ContributorLevel: String, Codable, CaseIterable, Sendable {
    case novice
    case knower
    case expert
    case keeper

    public var titleKey: String { "level.\(rawValue)" }

    public var systemImage: String {
        switch self {
        case .novice: "leaf"
        case .knower: "star"
        case .expert: "star.circle.fill"
        case .keeper: "crown.fill"
        }
    }

    /// С каких очков начинается уровень.
    public var threshold: Int {
        switch self {
        case .novice: 0
        case .knower: 50
        case .expert: 200
        case .keeper: 500
        }
    }
}

/// Свой вклад (`my_contribution`): очки по видам, уровень, порог следующего, очередь правок.
public struct Contribution: Codable, Equatable, Sendable {
    public let points: Int
    public let level: ContributorLevel
    /// `nil` — уровень наивысший.
    public let nextLevelPoints: Int?
    public let places: Int
    public let photos: Int
    public let reports: Int
    public let reviews: Int
    public let edits: Int
    public let helpful: Int
    public let canReview: Bool
    public let reviewQueue: Int

    public init(
        points: Int, level: ContributorLevel, nextLevelPoints: Int?,
        places: Int = 0, photos: Int = 0, reports: Int = 0, reviews: Int = 0, edits: Int = 0, helpful: Int = 0,
        canReview: Bool = false, reviewQueue: Int = 0
    ) {
        self.points = points
        self.level = level
        self.nextLevelPoints = nextLevelPoints
        self.places = places
        self.photos = photos
        self.reports = reports
        self.reviews = reviews
        self.edits = edits
        self.helpful = helpful
        self.canReview = canReview
        self.reviewQueue = reviewQueue
    }

    enum CodingKeys: String, CodingKey {
        case points, level, places, photos, reports, reviews, edits, helpful
        case nextLevelPoints = "next_level_points"
        case canReview = "can_review"
        case reviewQueue = "review_queue"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = try c.decode(Int.self, forKey: .points)
        // Новый уровень из новой версии сервера — показываем как ближайший известный.
        level = (try? c.decode(ContributorLevel.self, forKey: .level)) ?? .novice
        nextLevelPoints = try c.decodeIfPresent(Int.self, forKey: .nextLevelPoints)
        places = try c.decodeIfPresent(Int.self, forKey: .places) ?? 0
        photos = try c.decodeIfPresent(Int.self, forKey: .photos) ?? 0
        reports = try c.decodeIfPresent(Int.self, forKey: .reports) ?? 0
        reviews = try c.decodeIfPresent(Int.self, forKey: .reviews) ?? 0
        edits = try c.decodeIfPresent(Int.self, forKey: .edits) ?? 0
        helpful = try c.decodeIfPresent(Int.self, forKey: .helpful) ?? 0
        canReview = try c.decodeIfPresent(Bool.self, forKey: .canReview) ?? false
        reviewQueue = try c.decodeIfPresent(Int.self, forKey: .reviewQueue) ?? 0
    }

    /// Уровень следующий за текущим.
    public var nextLevel: ContributorLevel? {
        let all = ContributorLevel.allCases
        guard let index = all.firstIndex(of: level), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    /// Доля пути до следующего уровня (0…1); на наивысшем — 1.
    public var progress: Double {
        guard let next = nextLevelPoints, next > level.threshold else { return 1 }
        return min(max(Double(points - level.threshold) / Double(next - level.threshold), 0), 1)
    }
}

/// Правка места в очереди опытного (`suggestion_review_queue`).
public struct SuggestionReviewItem: Decodable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let placeID: UUID
    public let placeName: String
    public let placeType: PlaceType?
    public let placeDescription: String?
    /// Что предлагают: новое название, тип, описание; поменять «Информацию» о месте.
    public let newName: String?
    public let newType: PlaceType?
    public let newDescription: String?
    public let changesAttributes: Bool
    public let note: String?
    public let authorUsername: String?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, changes, note
        case placeID = "place_id"
        case placeName = "place_name"
        case placeType = "place_type"
        case placeDescription = "place_description"
        case authorUsername = "author_username"
        case createdAt = "created_at"
    }

    enum ChangeKeys: String, CodingKey {
        case name, type, description, attributes
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        placeID = try c.decode(UUID.self, forKey: .placeID)
        placeName = try c.decode(String.self, forKey: .placeName)
        placeType = try? c.decodeIfPresent(PlaceType.self, forKey: .placeType)
        placeDescription = try c.decodeIfPresent(String.self, forKey: .placeDescription)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        authorUsername = try c.decodeIfPresent(String.self, forKey: .authorUsername)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        let changes = try c.nestedContainer(keyedBy: ChangeKeys.self, forKey: .changes)
        newName = try changes.decodeIfPresent(String.self, forKey: .name)
        newType = try? changes.decodeIfPresent(PlaceType.self, forKey: .type)
        newDescription = try changes.decodeIfPresent(String.self, forKey: .description)
        changesAttributes = changes.contains(.attributes)
    }
}
