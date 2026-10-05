import Foundation

// MARK: - Совместные сборы

/// Общие сборы в списке (RPC `my_shared_packings`): свои и куда пригласили, с прогрессом.
public struct SharedPackingSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let ownerID: UUID
    public let ownerUsername: String?
    public let ownerDisplayName: String?
    public let title: String
    public let tripDate: CalendarDay?
    public let membersCount: Int
    public let itemsCount: Int
    public let doneCount: Int
    public let isOwn: Bool
    public let updatedAt: Date

    public var ownerName: String? {
        ownerDisplayName ?? ownerUsername.map { "@" + $0 }
    }

    public init(
        id: UUID,
        ownerID: UUID,
        ownerUsername: String?,
        ownerDisplayName: String?,
        title: String,
        tripDate: CalendarDay?,
        membersCount: Int,
        itemsCount: Int,
        doneCount: Int,
        isOwn: Bool,
        updatedAt: Date
    ) {
        self.id = id
        self.ownerID = ownerID
        self.ownerUsername = ownerUsername
        self.ownerDisplayName = ownerDisplayName
        self.title = title
        self.tripDate = tripDate
        self.membersCount = membersCount
        self.itemsCount = itemsCount
        self.doneCount = doneCount
        self.isOwn = isOwn
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case ownerUsername = "owner_username"
        case ownerDisplayName = "owner_display_name"
        case title
        case tripDate = "trip_date"
        case membersCount = "members_count"
        case itemsCount = "items_count"
        case doneCount = "done_count"
        case isOwn = "is_own"
        case updatedAt = "updated_at"
    }
}

/// Пункт общих сборов: кто берёт и собрано ли.
public struct SharedPackingItem: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    /// Категория экипировки (`GearCategory.rawValue`) — для группировки, как в своих сборах.
    public var category: String?
    public var position: Int
    public var assigneeID: UUID?
    public var done: Bool
    public var createdBy: UUID?

    public init(id: UUID, title: String, category: String?, position: Int, assigneeID: UUID?, done: Bool, createdBy: UUID?) {
        self.id = id
        self.title = title
        self.category = category
        self.position = position
        self.assigneeID = assigneeID
        self.done = done
        self.createdBy = createdBy
    }

    public var gearCategory: GearCategory? {
        category.flatMap(GearCategory.init(rawValue:))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case position = "item_position"
        case assigneeID = "assignee_id"
        case done
        case createdBy = "created_by"
    }
}

/// Участник общих сборов.
public struct SharedPackingMember: Codable, Identifiable, Hashable, Sendable {
    public let userID: UUID
    public let username: String?
    public let displayName: String?
    public let avatarPath: String?
    public let isOwner: Bool

    public var id: UUID { userID }

    public var name: String? {
        displayName ?? username.map { "@" + $0 }
    }

    public init(userID: UUID, username: String?, displayName: String?, avatarPath: String?, isOwner: Bool) {
        self.userID = userID
        self.username = username
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.isOwner = isOwner
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case isOwner = "is_owner"
    }
}

public enum SharedPacking {
    /// Пункты своего чеклиста для `share_packing`: название и категория, без галочек — в общих
    /// сборах каждый отмечает заново.
    public static func items(from checklist: Checklist) -> [SharedPackingItemDraft] {
        checklist.items.map { SharedPackingItemDraft(title: $0.title, category: $0.category?.rawValue) }
    }

    /// Пункты по категориям в порядке категорий экипировки; без категории — в конце.
    public static func grouped(_ items: [SharedPackingItem]) -> [(category: GearCategory?, items: [SharedPackingItem])] {
        let sorted = items.sorted { ($0.position, $0.id.uuidString) < ($1.position, $1.id.uuidString) }
        var result: [(category: GearCategory?, items: [SharedPackingItem])] = []
        for category in GearCategory.allCases {
            let inCategory = sorted.filter { $0.gearCategory == category }
            if !inCategory.isEmpty { result.append((category, inCategory)) }
        }
        let rest = sorted.filter { $0.gearCategory == nil }
        if !rest.isEmpty { result.append((nil, rest)) }
        return result
    }

    /// Пункты без хозяина — «кто возьмёт?».
    public static func unassignedCount(_ items: [SharedPackingItem]) -> Int {
        items.filter { $0.assigneeID == nil }.count
    }
}

/// Пункт для `share_packing`.
public struct SharedPackingItemDraft: Codable, Hashable, Sendable {
    public let title: String
    public let category: String?

    public init(title: String, category: String?) {
        self.title = title
        self.category = category
    }
}
