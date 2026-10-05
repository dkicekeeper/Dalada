import DaladaCore
import Foundation
import Supabase

// MARK: - Совместные сборы

extension BackendClient {
    /// Поделиться сборами с друзьями: копия пунктов на сервере. Возвращает id общих сборов.
    public func sharePacking(
        title: String,
        tripDate: CalendarDay?,
        items: [SharedPackingItemDraft],
        members: [UUID]
    ) async throws -> UUID {
        try await supabase
            .rpc("share_packing", params: SharePackingParams(title: title, tripDate: tripDate, items: items, members: members))
            .execute()
            .value
    }

    public func mySharedPackings() async throws -> [SharedPackingSummary] {
        try await supabase.rpc("my_shared_packings").execute().value
    }

    public func sharedPackingMembers(_ packingID: UUID) async throws -> [SharedPackingMember] {
        try await supabase.rpc("shared_packing_members", params: ["p_packing": packingID]).execute().value
    }

    public func sharedPackingItems(_ packingID: UUID) async throws -> [SharedPackingItem] {
        try await supabase.rpc("shared_packing_items", params: ["p_packing": packingID]).execute().value
    }

    /// «Возьму я» (`take`) или «не беру».
    public func takePackingItem(_ itemID: UUID, take: Bool) async throws {
        try await supabase
            .rpc("take_packing_item", params: PackingItemFlagParams(item: itemID, flag: take, key: .take))
            .execute()
    }

    public func setPackingItemDone(_ itemID: UUID, done: Bool) async throws {
        try await supabase
            .rpc("set_packing_item_done", params: PackingItemFlagParams(item: itemID, flag: done, key: .done))
            .execute()
    }

    public func addPackingItem(_ packingID: UUID, title: String, category: String? = nil) async throws -> UUID {
        try await supabase
            .rpc("add_packing_item", params: AddPackingItemParams(packing: packingID, title: title, category: category))
            .execute()
            .value
    }

    public func deletePackingItem(_ itemID: UUID) async throws {
        try await supabase.rpc("delete_packing_item", params: ["p_item": itemID]).execute()
    }

    /// Выйти (участник) или удалить сборы целиком (автор).
    public func leaveSharedPacking(_ packingID: UUID) async throws {
        try await supabase.rpc("leave_shared_packing", params: ["p_packing": packingID]).execute()
    }
}

struct SharePackingParams: Encodable, Sendable {
    let title: String
    let tripDate: CalendarDay?
    let items: [SharedPackingItemDraft]
    let members: [UUID]

    enum CodingKeys: String, CodingKey {
        case title = "p_title"
        case tripDate = "p_trip_date"
        case items = "p_items"
        case members = "p_members"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(tripDate, forKey: .tripDate)
        try c.encode(items, forKey: .items)
        try c.encode(members, forKey: .members)
    }
}

struct PackingItemFlagParams: Encodable, Sendable {
    enum Key { case take, done }

    let item: UUID
    let flag: Bool
    let key: Key

    enum CodingKeys: String, CodingKey {
        case item = "p_item"
        case take = "p_take"
        case done = "p_done"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(item, forKey: .item)
        try c.encode(flag, forKey: key == .take ? .take : .done)
    }
}

struct AddPackingItemParams: Encodable, Sendable {
    let packing: UUID
    let title: String
    let category: String?

    enum CodingKeys: String, CodingKey {
        case packing = "p_packing"
        case title = "p_title"
        case category = "p_category"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(packing, forKey: .packing)
        try c.encode(title, forKey: .title)
        try c.encode(category, forKey: .category)
    }
}
