import DaladaCore
import Foundation
import Supabase

// MARK: - Правила и запреты

extension BackendClient {
    /// Все зоны и правила (справочник для всех, в том числе гостей). Незнакомые записи из новой
    /// версии сервера пропускаются.
    public func rulesPack() async throws -> RulesPack {
        async let zones: [Lenient<RuleZone>] = supabase
            .from("rule_zones")
            .select("id,kind,basin,name_ru,name_kk,name_en,note_ru,note_kk,note_en,geom,sort_order")
            .execute()
            .value
        async let regulations: [Lenient<Regulation>] = supabase
            .from("regulations")
            .select(
                "id,kind,basin,zone_ids,gear,start_month,start_day,end_month,end_day,min_sizes," +
                "title_ru,title_kk,title_en,body_ru,body_kk,body_en,source_title,source_url,source_clause," +
                "verified_on,sort_order"
            )
            .execute()
            .value
        return try await RulesPack(
            zones: zones.compactMap(\.value),
            regulations: regulations.compactMap(\.value)
        )
    }

    /// Нацпарки, заповедник, погранзона и МРП (справочник для всех). Незнакомые записи пропускаются.
    public func mapAreasPack() async throws -> MapAreasPack {
        async let areas: [Lenient<MapArea>] = supabase
            .from("map_areas")
            .select(
                "id,kind,name_ru,name_kk,name_en,info_ru,info_kk,info_en,fee_person_mrp,fee_car_mrp," +
                "fee_fishing_mrp,website_url,tickets_url,source_title,source_url,verified_on,sort_order,geom"
            )
            .execute()
            .value
        async let mrp: [MRPValue] = supabase
            .from("mrp_values")
            .select("year,tenge")
            .execute()
            .value
        return try await MapAreasPack(areas: areas.compactMap(\.value), mrp: mrp)
    }
}
