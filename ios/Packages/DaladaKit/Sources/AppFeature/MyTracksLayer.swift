import Backend
import DaladaCore
import Foundation
import Observation
import Persistence

/// Слой «Мои треки»: сохранённая копия (видна без сети), потом свежие с сервера — при включении
/// слоя и не чаще раза в 10 минут, чтобы новая поездка появилась без перезапуска.
@MainActor
@Observable
final class MyTracksLayer {
    /// Отрезки всех треков — одной линией на карте.
    private(set) var segments: [[GeoPoint]] = []

    private let backend: BackendClient?
    private let cache: CacheStore?
    private var loadedFor: UUID?
    private var refreshedAt: Date?
    private var isLoading = false

    init(backend: BackendClient?, cache: CacheStore?) {
        self.backend = backend
        self.cache = cache
    }

    /// Загрузить треки этого человека; `nil` (гость) — слой пустой.
    func load(for userID: UUID?) async {
        guard let userID else {
            segments = []
            loadedFor = nil
            return
        }
        let key = CacheKey.myTracks(userID)
        if loadedFor != userID {
            loadedFor = userID
            refreshedAt = nil
            segments = TrackLine.segments((try? await cache?.load([TrackLine].self, for: key)) ?? [])
        }
        guard let backend, !isLoading else { return }
        if let refreshedAt, Date().timeIntervalSince(refreshedAt) < 600 { return }
        isLoading = true
        defer { isLoading = false }
        guard let lines = try? await backend.myTracks(), loadedFor == userID else { return }
        segments = TrackLine.segments(lines)
        refreshedAt = Date()
        try? await cache?.save(lines, for: key)
    }
}
