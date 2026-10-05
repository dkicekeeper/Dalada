import DaladaCore
import Foundation
import Supabase

extension BackendClient {
    /// Свои фото (отчёты, уловы, отзывы), новые сверху; `after` — последнее показанное (следующая страница).
    public func myPhotos(limit: Int = 60, after last: MyPhoto? = nil) async throws -> [MyPhoto] {
        try await supabase
            .rpc("my_photos", params: MyPhotosParams(limit: limit, after: last))
            .execute()
            .value
    }
}

struct MyPhotosParams: Encodable, Sendable {
    let limit: Int
    let after: MyPhoto?

    enum CodingKeys: String, CodingKey {
        case limit = "p_limit"
        case after = "p_after"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(limit, forKey: .limit)
        try c.encodeIfPresent(after?.id, forKey: .after)
    }
}
