import Foundation

// MARK: - Трансляция геопозиции друзьям

/// Друг, который сейчас показывает мне, где он (RPC `friends_live_locations`). Координат нет, пока
/// он не прислал точку или пока он в своей зоне приватности.
public struct FriendLiveLocation: Codable, Identifiable, Hashable, Sendable {
    public let ownerID: UUID
    public let username: String?
    public let displayName: String?
    public let avatarPath: String?
    public let latitude: Double?
    public let longitude: Double?
    public let accuracyM: Double?
    /// Время последней точки.
    public let updatedAt: Date?
    public let startedAt: Date
    public let expiresAt: Date
    public let inPrivacyZone: Bool

    public var id: UUID { ownerID }

    public var coordinate: GeoPoint? {
        guard let latitude, let longitude else { return nil }
        return GeoPoint(latitude: latitude, longitude: longitude)
    }

    /// Имя для подписи: имя, иначе @username.
    public var name: String? {
        displayName ?? username.map { "@" + $0 }
    }

    public init(
        ownerID: UUID,
        username: String?,
        displayName: String?,
        avatarPath: String?,
        latitude: Double?,
        longitude: Double?,
        accuracyM: Double?,
        updatedAt: Date?,
        startedAt: Date,
        expiresAt: Date,
        inPrivacyZone: Bool
    ) {
        self.ownerID = ownerID
        self.username = username
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyM = accuracyM
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.inPrivacyZone = inPrivacyZone
    }

    enum CodingKeys: String, CodingKey {
        case ownerID = "owner_id"
        case username
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case latitude
        case longitude
        case accuracyM = "accuracy_m"
        case updatedAt = "updated_at"
        case startedAt = "started_at"
        case expiresAt = "expires_at"
        case inPrivacyZone = "in_privacy_zone"
    }
}

/// Своя трансляция (RPC `my_live_share`): до какого времени, когда была последняя точка, кому видна.
public struct MyLiveShare: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let expiresAt: Date
    public var updatedAt: Date?
    public let viewerIDs: [UUID]

    public init(startedAt: Date, expiresAt: Date, updatedAt: Date?, viewerIDs: [UUID]) {
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.updatedAt = updatedAt
        self.viewerIDs = viewerIDs
    }

    public func isActive(at now: Date) -> Bool { expiresAt > now }

    enum CodingKeys: String, CodingKey {
        case startedAt = "started_at"
        case expiresAt = "expires_at"
        case updatedAt = "updated_at"
        case viewerIDs = "viewer_ids"
    }
}

/// Когда отправлять точку: не чаще раза в минуту; при движении от 150 м — сразу после минуты, а на
/// месте — раз в 5 минут, чтобы друзья видели, что связь есть. Батарея и сеть — бережём.
public enum LiveSharePolicy {
    public static let minInterval: TimeInterval = 60
    public static let heartbeat: TimeInterval = 5 * 60
    public static let minDistanceM = 150.0
    /// На сколько часов включается трансляция.
    public static let defaultHours = 12

    public static func shouldSend(lastPoint: GeoPoint?, lastSentAt: Date?, point: GeoPoint, at now: Date) -> Bool {
        guard let lastPoint, let lastSentAt else { return true }
        let elapsed = now.timeIntervalSince(lastSentAt)
        if elapsed < minInterval { return false }
        if elapsed >= heartbeat { return true }
        return lastPoint.distance(to: point) >= minDistanceM
    }
}
