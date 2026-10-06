import DaladaCore
import Foundation
import Supabase

// MARK: - Экспорт

extension BackendClient {
    /// Точки своей поездки для GPX: долгота, широта, высота, время (чужая — 42501).
    public func myTripPoints(_ tripID: UUID) async throws -> [ExportedTrackPoint] {
        try await supabase
            .rpc("my_trip_points", params: ["p_trip": tripID])
            .execute()
            .value
    }

    /// Все свои данные одним JSON (`export_my_data`) — как есть, для `data.json` в архиве.
    public func exportMyData() async throws -> Data {
        try await supabase
            .rpc("export_my_data")
            .execute()
            .data
    }

    /// Своё фото из бакета `media` — для архива.
    public func downloadMedia(path: String) async throws -> Data {
        try await supabase.storage.from(MediaPath.bucket).download(path: path)
    }
}
