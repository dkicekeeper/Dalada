import DaladaCore
import Foundation
import Supabase

// MARK: - Участники поездки и личные рекорды (M15)

extension BackendClient {
    /// Отметить друзей в своей поездке. Не друзья пропускаются; уже отмеченные — без изменений.
    /// Возвращает, скольких отметили сейчас.
    @discardableResult
    public func tagTripFriends(tripID: UUID, userIDs: [UUID]) async throws -> Int {
        try await supabase
            .rpc("tag_trip_friends", params: TripTagParams(trip: tripID, users: userIDs))
            .execute()
            .value
    }

    /// Убрать отметку со своей поездки.
    public func untagTripFriend(tripID: UUID, userID: UUID) async throws {
        try await supabase
            .rpc("untag_trip_friend", params: ["p_trip": tripID, "p_user": userID])
            .execute()
    }

    /// Принять или отклонить отметку; «выйти из поездки» — отклонить после принятия.
    public func respondTripTag(tripID: UUID, accept: Bool) async throws {
        try await supabase
            .rpc("respond_trip_tag", params: TripTagResponseParams(trip: tripID, accept: accept))
            .execute()
    }

    /// Участники поездки, которых видит зритель.
    public func tripParticipants(tripID: UUID) async throws -> [TripParticipant] {
        try await supabase
            .rpc("trip_participants", params: ["p_trip": tripID])
            .execute()
            .value
    }

    /// Поездки, где меня отметили, а я ещё не ответил.
    public func myTripInvitations() async throws -> [TripInvitation] {
        try await supabase.rpc("my_trip_invitations").execute().value
    }

    /// Чужие поездки, в которых я участник.
    public func myJoinedTrips(limit: Int = 50) async throws -> [JoinedTrip] {
        try await supabase
            .rpc("my_joined_trips", params: ["p_limit": limit])
            .execute()
            .value
    }

    /// Личные рекорды по видам.
    public func myRecords() async throws -> [PersonalRecord] {
        try await supabase.rpc("my_records").execute().value
    }
}

private struct TripTagParams: Encodable, Sendable {
    let trip: UUID
    let users: [UUID]

    enum CodingKeys: String, CodingKey {
        case trip = "p_trip"
        case users = "p_users"
    }
}

private struct TripTagResponseParams: Encodable, Sendable {
    let trip: UUID
    let accept: Bool

    enum CodingKeys: String, CodingKey {
        case trip = "p_trip"
        case accept = "p_accept"
    }
}
