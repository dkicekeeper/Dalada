import Foundation

/// Трек своей поездки для слоя «Мои треки» — строка `my_tracks`: упрощённая линия без высоты и
/// времени, только для рисования на карте.
public struct TrackLine: Codable, Hashable, Sendable, Identifiable {
    /// Поездка.
    public let id: UUID
    public let activity: TripActivity
    public let startedAt: Date
    public let segments: [[GeoPoint]]

    public init(id: UUID, activity: TripActivity, startedAt: Date, segments: [[GeoPoint]]) {
        self.id = id
        self.activity = activity
        self.startedAt = startedAt
        self.segments = segments.filter { $0.count >= 2 }
    }

    enum CodingKeys: String, CodingKey {
        case id = "trip_id"
        case activity
        case startedAt = "started_at"
        case track
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        // Новый вид поездки в старом приложении — рисуем как «другое».
        activity = (try? c.decode(TripActivity.self, forKey: .activity)) ?? .other
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        segments = (try c.decodeIfPresent(TrackGeometry.self, forKey: .track)?.segments ?? []).filter { $0.count >= 2 }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(activity, forKey: .activity)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(segments.isEmpty ? nil : TrackGeometry(segments: segments), forKey: .track)
    }

    /// Все отрезки всех треков — для одной линии на карте.
    public static func segments(_ lines: [TrackLine]) -> [[GeoPoint]] {
        lines.flatMap(\.segments)
    }
}
