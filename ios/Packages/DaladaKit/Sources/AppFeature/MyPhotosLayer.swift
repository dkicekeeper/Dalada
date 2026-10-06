import Backend
import DaladaCore
import Foundation
import MapEngine
import Observation
import Persistence
import SwiftUI

/// Слой «Мои фото»: сохранённая копия (видна без сети), потом свежие с сервера — при включении слоя
/// и не чаще раза в 10 минут.
@MainActor
@Observable
final class MyPhotosLayer {
    private(set) var points: [MyPhotoPoint] = []

    private let backend: BackendClient?
    private let cache: CacheStore?
    private var loadedFor: UUID?
    private var refreshedAt: Date?
    private var isLoading = false

    init(backend: BackendClient?, cache: CacheStore?) {
        self.backend = backend
        self.cache = cache
    }

    /// Точки для карты.
    var mapPhotos: [MapPhoto] {
        points.map { MapPhoto(id: $0.id, coordinate: $0.coordinate) }
    }

    func point(_ id: UUID) -> MyPhotoPoint? {
        points.first { $0.id == id }
    }

    /// Загрузить фото этого человека; `nil` (гость) — слой пустой.
    func load(for userID: UUID?) async {
        guard let userID else {
            points = []
            loadedFor = nil
            return
        }
        let key = CacheKey.myPhotoPoints(userID)
        if loadedFor != userID {
            loadedFor = userID
            refreshedAt = nil
            points = (try? await cache?.load([MyPhotoPoint].self, for: key)) ?? []
        }
        guard let backend, !isLoading else { return }
        if let refreshedAt, Date().timeIntervalSince(refreshedAt) < 600 { return }
        isLoading = true
        defer { isLoading = false }
        guard let loaded = try? await backend.myPhotoPoints(), loadedFor == userID else { return }
        points = loaded
        refreshedAt = Date()
        try? await cache?.save(loaded, for: key)
    }
}

/// Фото с карты на весь экран: ссылки на файл — при открытии.
struct MapPhotoViewer: View {
    let point: MyPhotoPoint
    let environment: AppEnvironment

    @State private var urls: [String: URL] = [:]

    var body: some View {
        PhotoViewer(media: [point.photo.reportMedia], urls: urls, selection: point.id)
            .task {
                guard let backend = environment.backend else { return }
                urls = (try? await backend.signedMediaURLs(paths: [point.photo.thumbnailPath, point.photo.path])) ?? [:]
            }
    }
}
