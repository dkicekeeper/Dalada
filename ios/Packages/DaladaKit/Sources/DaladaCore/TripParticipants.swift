import Foundation

/// Отметка друга в поездке (`public.trip_participant_status`).
public enum TripParticipantStatus: String, Codable, Sendable {
    /// Отмечен, ещё не ответил.
    case pending
    case accepted
    /// Отклонил или вышел из поездки — снова отметить нельзя.
    case declined
}

/// Участник поездки — строка `trip_participants`. Автору видны ждущие ответа и принявшие, другим —
/// принявшие и сам зритель, если его отметили.
public struct TripParticipant: Codable, Identifiable, Hashable, Sendable {
    public let userID: UUID
    public let username: String?
    public let displayName: String?
    public let avatarPath: String?
    public let status: TripParticipantStatus
    public let isMe: Bool

    public var id: UUID { userID }

    public init(
        userID: UUID,
        username: String?,
        displayName: String?,
        avatarPath: String? = nil,
        status: TripParticipantStatus,
        isMe: Bool = false
    ) {
        self.userID = userID
        self.username = username
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.status = status
        self.isMe = isMe
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case status
        case isMe = "is_me"
    }
}

/// Сколько друзей можно отметить в одной поездке (`private.trip_participants_limit`).
public enum TripParticipants {
    public static let limit = 20

    /// Моя отметка в поездке (если меня отметили).
    public static func mine(in participants: [TripParticipant]) -> TripParticipant? {
        participants.first(where: \.isMe)
    }
}

/// Приглашение: меня отметили в поездке, я ещё не ответил — строка `my_trip_invitations`.
public struct TripInvitation: Codable, Identifiable, Hashable, Sendable {
    public let tripID: UUID
    public let title: String
    public let activity: TripActivity
    public let startedAt: Date
    public let endedAt: Date
    public let owner: TripOwner
    public let taggedAt: Date

    public var id: UUID { tripID }

    public init(
        tripID: UUID,
        title: String,
        activity: TripActivity,
        startedAt: Date,
        endedAt: Date,
        owner: TripOwner,
        taggedAt: Date
    ) {
        self.tripID = tripID
        self.title = title
        self.activity = activity
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.owner = owner
        self.taggedAt = taggedAt
    }

    enum CodingKeys: String, CodingKey {
        case tripID = "trip_id"
        case title
        case activity
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case ownerID = "owner_id"
        case ownerUsername = "owner_username"
        case ownerDisplayName = "owner_display_name"
        case ownerAvatarPath = "owner_avatar_path"
        case taggedAt = "tagged_at"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tripID = try c.decode(UUID.self, forKey: .tripID)
        title = try c.decode(String.self, forKey: .title)
        activity = try c.decode(TripActivity.self, forKey: .activity)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decode(Date.self, forKey: .endedAt)
        owner = TripOwner(
            id: try c.decode(UUID.self, forKey: .ownerID),
            username: try c.decodeIfPresent(String.self, forKey: .ownerUsername),
            displayName: try c.decodeIfPresent(String.self, forKey: .ownerDisplayName),
            avatarPath: try c.decodeIfPresent(String.self, forKey: .ownerAvatarPath)
        )
        taggedAt = try c.decode(Date.self, forKey: .taggedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tripID, forKey: .tripID)
        try c.encode(title, forKey: .title)
        try c.encode(activity, forKey: .activity)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(owner.id, forKey: .ownerID)
        try c.encodeIfPresent(owner.username, forKey: .ownerUsername)
        try c.encodeIfPresent(owner.displayName, forKey: .ownerDisplayName)
        try c.encodeIfPresent(owner.avatarPath, forKey: .ownerAvatarPath)
        try c.encode(taggedAt, forKey: .taggedAt)
    }
}

/// Чужая поездка, в которой я участник (принял отметку), — строка `my_joined_trips`.
public struct JoinedTrip: Codable, Identifiable, Hashable, Sendable {
    public let summary: TripSummary
    /// Автор поездки.
    public let host: TripOwner

    public var id: UUID { summary.id }

    public init(summary: TripSummary, host: TripOwner) {
        self.summary = summary
        self.host = host
    }

    enum CodingKeys: String, CodingKey {
        case hostID = "host_id"
        case hostUsername = "host_username"
        case hostDisplayName = "host_display_name"
        case hostAvatarPath = "host_avatar_path"
    }

    public init(from decoder: any Decoder) throws {
        summary = try TripSummary(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = TripOwner(
            id: try c.decode(UUID.self, forKey: .hostID),
            username: try c.decodeIfPresent(String.self, forKey: .hostUsername),
            displayName: try c.decodeIfPresent(String.self, forKey: .hostDisplayName),
            avatarPath: try c.decodeIfPresent(String.self, forKey: .hostAvatarPath)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        try summary.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(host.id, forKey: .hostID)
        try c.encodeIfPresent(host.username, forKey: .hostUsername)
        try c.encodeIfPresent(host.displayName, forKey: .hostDisplayName)
        try c.encodeIfPresent(host.avatarPath, forKey: .hostAvatarPath)
    }
}

/// Строка «Моих поездок»: своя или чужая, где я участник. Новые сверху.
public enum TripListEntry: Identifiable, Hashable, Sendable {
    case own(TripSummary)
    case joined(JoinedTrip)

    public var id: UUID { summary.id }

    public var summary: TripSummary {
        switch self {
        case .own(let trip): trip
        case .joined(let trip): trip.summary
        }
    }

    /// Автор чужой поездки (`nil` — своя).
    public var host: TripOwner? {
        if case .joined(let trip) = self { return trip.host }
        return nil
    }

    /// Свои и чужие поездки одним списком, новые сверху; одна поездка — один раз.
    public static func merged(own: [TripSummary], joined: [JoinedTrip]) -> [TripListEntry] {
        let ownIDs = Set(own.map(\.id))
        let entries = own.map(TripListEntry.own) + joined.filter { !ownIDs.contains($0.id) }.map(TripListEntry.joined)
        return entries.sorted { $0.summary.startedAt > $1.summary.startedAt }
    }
}
