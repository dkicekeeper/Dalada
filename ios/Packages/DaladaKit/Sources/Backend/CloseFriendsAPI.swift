import DaladaCore
import Foundation
import Supabase

// MARK: - Близкие друзья

extension BackendClient {
    /// Свой список «Близкие»: кому видно то, что отмечено «Близкие».
    public func closeFriendIDs() async throws -> Set<UUID> {
        let rows: [CloseFriendRow] = try await supabase
            .from("close_friends")
            .select("friend_id")
            .execute()
            .value
        return Set(rows.map(\.friendID))
    }

    /// Добавить друга в «Близкие» (только друзей; иначе 22023).
    public func addCloseFriend(_ friendID: UUID) async throws {
        try await supabase
            .from("close_friends")
            .insert(["friend_id": friendID], returning: .minimal)
            .execute()
    }

    public func removeCloseFriend(_ friendID: UUID) async throws {
        try await supabase
            .from("close_friends")
            .delete()
            .eq("friend_id", value: friendID)
            .execute()
    }
}

struct CloseFriendRow: Decodable, Sendable {
    let friendID: UUID

    enum CodingKeys: String, CodingKey {
        case friendID = "friend_id"
    }
}
