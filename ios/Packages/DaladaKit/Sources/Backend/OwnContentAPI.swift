import DaladaCore
import Foundation
import Supabase

// MARK: - Правка и удаление своего: место, отчёт, улов

extension BackendClient {
    /// Удалить своё место: оно пропадает с карты и из списков. Свои отчёты и уловы в нём остаются
    /// в профиле.
    public func deletePlace(_ placeID: UUID) async throws {
        try await supabase
            .from("places")
            .update(["deleted_at": PostgresTimestamp.string(Date())])
            .eq("id", value: placeID)
            .execute()
    }

    /// Удалить свой отчёт целиком — вместе с его уловами и фото (RPC `delete_checkin`).
    public func deleteReport(_ checkinID: UUID) async throws {
        try await supabase
            .rpc("delete_checkin", params: ["p_checkin": checkinID])
            .execute()
    }

    /// Удалить свой улов.
    public func deleteCatch(_ catchID: UUID) async throws {
        try await supabase
            .from("catches")
            .update(["deleted_at": PostgresTimestamp.string(Date())])
            .eq("id", value: catchID)
            .execute()
    }

    /// Свой улов для правки — все поля формы. `nil` — улова нет или он удалён.
    public func ownCatch(_ catchID: UUID) async throws -> CatchDraft? {
        let rows: [OwnCatchRow] = try await supabase
            .from("catches")
            .select("id,species_id,weight_g,length_mm,count,method,bait,released,hide_size,deleted_at")
            .eq("id", value: catchID)
            .execute()
            .value
        return rows.first(where: { $0.deletedAt == nil })?.draft
    }

    /// Свой отчёт для правки: условия, заметка, видимость. `nil` — отчёта нет или он удалён.
    public func ownReport(_ checkinID: UUID) async throws -> ReportEdit? {
        let rows: [OwnReportRow] = try await supabase
            .from("checkins")
            .select("id,conditions,note,visibility,deleted_at")
            .eq("id", value: checkinID)
            .execute()
            .value
        return rows.first(where: { $0.deletedAt == nil })?.edit
    }

    /// Сохранить правку своего отчёта.
    public func updateReport(_ edit: ReportEdit) async throws {
        try await supabase
            .from("checkins")
            .update(ReportUpdate(edit))
            .eq("id", value: edit.id)
            .execute()
    }

    /// Сохранить правку своего улова (фото улова здесь не меняется).
    public func updateCatch(_ draft: CatchDraft) async throws {
        try await supabase
            .from("catches")
            .update(CatchUpdate(draft))
            .eq("id", value: draft.id)
            .execute()
    }
}

struct OwnCatchRow: Decodable, Sendable {
    let id: UUID
    let speciesID: String
    let weightGrams: Int?
    let lengthMillimeters: Int?
    let count: Int
    let method: String?
    let bait: String?
    let released: Bool
    let hideSize: Bool
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case speciesID = "species_id"
        case weightGrams = "weight_g"
        case lengthMillimeters = "length_mm"
        case count
        case method
        case bait
        case released
        case hideSize = "hide_size"
        case deletedAt = "deleted_at"
    }

    var draft: CatchDraft {
        CatchDraft(
            id: id,
            speciesID: speciesID,
            weightKg: weightGrams.map { Double($0) / 1000 },
            lengthCm: lengthMillimeters.map { Double($0) / 10 },
            count: count,
            method: method.flatMap(FishingMethod.init(rawValue:)),
            bait: bait ?? "",
            released: released,
            hideSize: hideSize
        )
    }
}

/// Поля улова для `update`: пустой вес, длина, способ и наживка — `null` (стёрли).
struct CatchUpdate: Encodable, Sendable {
    let draft: CatchDraft

    init(_ draft: CatchDraft) {
        self.draft = draft
    }

    enum CodingKeys: String, CodingKey {
        case speciesID = "species_id"
        case weightGrams = "weight_g"
        case lengthMillimeters = "length_mm"
        case count
        case method
        case bait
        case released
        case hideSize = "hide_size"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(draft.speciesID, forKey: .speciesID)
        try c.encode(draft.weightGrams, forKey: .weightGrams)
        try c.encode(draft.lengthMillimeters, forKey: .lengthMillimeters)
        try c.encode(draft.count, forKey: .count)
        try c.encode(draft.method, forKey: .method)
        let bait = draft.bait.trimmingCharacters(in: .whitespacesAndNewlines)
        try c.encode(bait.isEmpty ? nil : bait, forKey: .bait)
        try c.encode(draft.released, forKey: .released)
        try c.encode(draft.hideSize, forKey: .hideSize)
    }
}

struct OwnReportRow: Decodable, Sendable {
    let id: UUID
    let conditions: CheckinConditions?
    let note: String?
    let visibility: Visibility
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case conditions
        case note
        case visibility
        case deletedAt = "deleted_at"
    }

    var edit: ReportEdit {
        ReportEdit(id: id, conditions: conditions ?? CheckinConditions(), note: note ?? "", visibility: visibility)
    }
}

/// Поля отчёта для `update`: условия целиком, стёртая заметка — `null`.
struct ReportUpdate: Encodable, Sendable {
    let edit: ReportEdit

    init(_ edit: ReportEdit) {
        self.edit = edit
    }

    enum CodingKeys: String, CodingKey {
        case conditions
        case note
        case visibility
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(edit.conditions, forKey: .conditions)
        try c.encode(edit.trimmedNote, forKey: .note)
        try c.encode(edit.visibility, forKey: .visibility)
    }
}
