import DaladaCore
import Foundation
import Supabase

// MARK: - Вклад, уровни, разбор правок

extension BackendClient {
    /// Свой вклад и уровень (`my_contribution`).
    public func myContribution() async throws -> Contribution? {
        let rows: [Contribution] = try await supabase.rpc("my_contribution").execute().value
        return rows.first
    }

    /// Правки мест, которые может разобрать опытный (с «Эксперта»; иначе 42501).
    public func suggestionReviewQueue() async throws -> [SuggestionReviewItem] {
        try await supabase.rpc("suggestion_review_queue").execute().value
    }

    /// Принять (меняет место) или отклонить правку из своей очереди.
    public func reviewSuggestion(_ id: UUID, accept: Bool, note: String? = nil) async throws {
        try await supabase
            .rpc("review_suggestion", params: ReviewSuggestionParams(id: id, accept: accept, note: note))
            .execute()
    }
}

struct ReviewSuggestionParams: Encodable {
    let id: UUID
    let accept: Bool
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case accept = "p_accept"
        case note = "p_note"
    }
}
