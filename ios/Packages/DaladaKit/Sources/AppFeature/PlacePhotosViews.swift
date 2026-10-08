import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

/// Фото в шапке карточки места: сначала фото редакции, потом посетителей; ряд превью и «Все фото».
/// Фото и ссылки загружает карточка места (вместе с отчётами).
struct PlacePhotosHeader: View {
    let photos: [PlaceGalleryPhoto]
    let urls: [String: URL]
    let placeID: UUID
    let placeName: String
    let environment: AppEnvironment

    @State private var opened: PlaceGalleryPhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            PhotoStrip(photos, size: 150, onOpen: { opened = $0 }) { photo in
                RemotePhoto(path: photo.thumbnailPath, url: urls[photo.thumbnailPath])
            }
            NavigationLink {
                PlacePhotosGrid(placeID: placeID, placeName: placeName, environment: environment)
            } label: {
                Label("place.photos.all", systemImage: "photo.on.rectangle")
                    .font(AppTypography.bodySmall)
            }
        }
        .fullScreenCover(item: $opened) { photo in
            PlacePhotoViewer(photos: photos, urls: urls, selection: photo.id, environment: environment)
        }
    }
}

/// «Все фото» места: фильтр (все, уловы, место), сетка превью, подгрузка при прокрутке. Фото
/// редакции — первыми (кроме фильтра «Уловы»).
struct PlacePhotosGrid: View {
    let placeID: UUID
    let placeName: String
    let environment: AppEnvironment

    @State private var kind: PlacePhotoKind = .all
    @State private var editorial: [EditorialPhoto] = []
    @State private var photos: [PlacePhoto] = []
    @State private var urls: [String: URL] = [:]
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var loadError: String?
    @State private var opened: PlaceGalleryPhoto?

    private var gallery: [PlaceGalleryPhoto] {
        PlaceGalleryPhoto.gallery(editorial: kind == .catches ? [] : editorial, visitors: photos)
    }

    private static let pageSize = 60

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                SegmentedPicker(
                    title: String(localized: "place.photos.title"),
                    selection: $kind,
                    options: PlacePhotoKind.allCases.map {
                        (label: String(localized: String.LocalizationValue($0.titleKey)), value: $0)
                    }
                )
                .screenPadding()

                if gallery.isEmpty {
                    if isLoading {
                        PhotoGridSkeleton(count: 12, style: .edgeToEdge)
                    } else {
                        EmptyState(
                            icon: loadError == nil ? "photo.on.rectangle" : "wifi.slash",
                            title: String(localized: "place.photos.empty.title"),
                            description: loadError ?? String(localized: "place.photos.empty.description")
                        )
                    }
                } else {
                    DesignComponents.PhotoGrid(
                        gallery,
                        style: .edgeToEdge,
                        onOpen: { opened = $0 },
                        onReachEnd: { Task { await loadMore() } }
                    ) { photo in
                        RemotePhoto(path: photo.thumbnailPath, url: urls[photo.thumbnailPath])
                    }
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(Text(verbatim: placeName))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: kind) { await reload() }
        .refreshable { await reload() }
        .fullScreenCover(item: $opened) { photo in
            PlacePhotoViewer(photos: gallery, urls: urls, selection: photo.id, environment: environment)
        }
    }

    private func reload() async {
        photos = []
        hasMore = true
        loadError = nil
        if editorial.isEmpty, let backend = environment.backend,
           let loaded = try? await backend.placeEditorialPhotos(placeID: placeID) {
            let signed = (try? await backend.signedMediaURLs(paths: loaded.flatMap { [$0.thumbnailPath, $0.path] })) ?? [:]
            urls.merge(signed) { _, new in new }
            editorial = loaded
        }
        await loadMore()
    }

    private func loadMore() async {
        guard let backend = environment.backend, hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await backend.placePhotos(
                placeID: placeID, kind: kind, limit: Self.pageSize, after: photos.last?.id
            )
            let signed = (try? await backend.signedMediaURLs(paths: page.flatMap { [$0.thumbnailPath, $0.path] })) ?? [:]
            urls.merge(signed) { _, new in new }
            photos += page.filter { new in !photos.contains { $0.id == new.id } }
            hasMore = page.count == Self.pageSize
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
            hasMore = false
        }
    }
}

/// Фото места на весь экран: листание; у фото посетителя — автор, дата, улов или отчёт и «Пожаловаться»,
/// у фото редакции — автор, лицензия и ссылка на Wikimedia Commons.
struct PlacePhotoViewer: View {
    let photos: [PlaceGalleryPhoto]
    let urls: [String: URL]
    let selection: UUID
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DesignComponents.PhotoViewer(photos, selection: selection) { photo in
            RemotePhoto(
                path: photo.path,
                url: urls[photo.path],
                contentMode: .fit,
                placeholderPath: photo.thumbnailPath
            )
        } caption: { item in
            caption(item)
        } actions: { (item: PlaceGalleryPhoto) -> ModerationMenu? in
            // Жалоба — на отчёт с этим фото; блокировка — автора. Своё фото и фото редакции — без меню.
            guard case .visitor(let photo) = item, !photo.isOwn else { return nil }
            return ModerationMenu(target: .checkin, targetID: photo.checkinID, author: photo.author, isToolbar: true) {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func caption(_ item: PlaceGalleryPhoto) -> some View {
        switch item {
        case .visitor(let photo):
            Text(verbatim: photo.authorName)
                .font(AppTypography.bodyEmphasis)
            HStack(spacing: AppSpacing.xs) {
                Text(photo.at, format: .dateTime.day().month(.wide).year())
                Text(verbatim: "·")
                Label(
                    LocalizedStringKey(photo.isCatch ? "place.photos.source.catch" : "place.photos.source.report"),
                    systemImage: photo.isCatch ? "fish" : "mappin.circle"
                )
            }
            .font(AppTypography.caption)
            .foregroundStyle(.white.opacity(0.8))
        case .editorial(let photo):
            EditorialPhotoCredit(photo: photo)
        }
    }
}

/// Подпись фото редакции: автор, лицензия (ссылкой) и источник — Wikimedia Commons.
private struct EditorialPhotoCredit: View {
    let photo: EditorialPhoto

    var body: some View {
        Text("place.photos.editorial.author \(photo.author)")
            .font(AppTypography.bodyEmphasis)
            .lineLimit(2)
        HStack(spacing: AppSpacing.xs) {
            if let licenseURL = photo.licenseURL {
                Link(destination: licenseURL) { Text(verbatim: photo.license).underline() }
            } else {
                Text(verbatim: photo.license)
            }
            Text(verbatim: "·")
            if let sourceURL = photo.sourceURL {
                Link(destination: sourceURL) { Text(verbatim: "Wikimedia Commons").underline() }
            } else {
                Text(verbatim: "Wikimedia Commons")
            }
        }
        .font(AppTypography.caption)
        .foregroundStyle(.white.opacity(0.8))
        .tint(.white)
    }
}
