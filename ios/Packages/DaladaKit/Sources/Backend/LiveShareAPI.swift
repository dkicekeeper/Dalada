import DaladaCore
import Foundation
import Supabase

// MARK: - Трансляция геопозиции друзьям

extension BackendClient {
    /// Начать трансляцию (или перезапустить с другим списком): видят только друзья из `viewers`.
    /// Возвращает, до какого времени она идёт.
    public func startLiveShare(viewers: [UUID], hours: Int = LiveSharePolicy.defaultHours) async throws -> Date {
        try await supabase
            .rpc("start_live_share", params: StartLiveShareParams(viewers: viewers, hours: hours))
            .execute()
            .value
    }

    /// Новая точка. `false` — трансляции уже нет (выключили или кончилась): присылать больше не нужно.
    public func updateLiveLocation(_ point: GeoPoint, accuracy: Double?) async throws -> Bool {
        try await supabase
            .rpc("update_live_location", params: LiveLocationParams(point: point, accuracy: accuracy))
            .execute()
            .value
    }

    /// Выключить трансляцию: точка и список зрителей удаляются.
    public func stopLiveShare() async throws {
        try await supabase.rpc("stop_live_share").execute()
    }

    /// Своя трансляция, если идёт.
    public func myLiveShare() async throws -> MyLiveShare? {
        let rows: [MyLiveShare] = try await supabase.rpc("my_live_share").execute().value
        return rows.first
    }

    /// Друзья, которые сейчас показывают мне, где они.
    public func friendsLiveLocations() async throws -> [FriendLiveLocation] {
        try await supabase.rpc("friends_live_locations").execute().value
    }
}

struct StartLiveShareParams: Encodable, Sendable {
    let viewers: [UUID]
    let hours: Int

    enum CodingKeys: String, CodingKey {
        case viewers = "p_viewers"
        case hours = "p_hours"
    }
}

struct LiveLocationParams: Encodable, Sendable {
    let point: GeoPoint
    let accuracy: Double?

    enum CodingKeys: String, CodingKey {
        case lon = "p_lon"
        case lat = "p_lat"
        case accuracy = "p_accuracy"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(point.longitude, forKey: .lon)
        try c.encode(point.latitude, forKey: .lat)
        try c.encode(accuracy.flatMap { $0 >= 0 ? $0 : nil }, forKey: .accuracy)
    }
}
