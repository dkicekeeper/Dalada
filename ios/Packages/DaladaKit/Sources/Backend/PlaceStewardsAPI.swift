import DaladaCore
import Foundation
import Supabase

// MARK: - Смотритель и рекорды места

extension BackendClient {
    /// Смотритель места; `nil` — нет (меньше трёх отчётов за 60 дней) или место закрыто.
    public func placeSteward(placeID: UUID) async throws -> PlaceSteward? {
        let rows: [PlaceSteward] = try await supabase
            .rpc("place_steward", params: ["p_place": placeID])
            .execute()
            .value
        return rows.first
    }

    /// Рекорды места: самый тяжёлый улов каждого вида с фото, самые тяжёлые — первыми.
    public func placeRecords(placeID: UUID) async throws -> [PlaceRecord] {
        let rows: [PlaceRecord] = try await supabase
            .rpc("place_records", params: ["p_place": placeID])
            .execute()
            .value
        return PlaceRecord.sorted(rows)
    }
}
