import DaladaCore
import Foundation
import Supabase

extension BackendClient {
    /// Треки своих поездок для слоя «Мои треки», новые сверху.
    public func myTracks(limit: Int = 300) async throws -> [TrackLine] {
        try await supabase
            .rpc("my_tracks", params: ["p_limit": limit])
            .execute()
            .value
    }
}
