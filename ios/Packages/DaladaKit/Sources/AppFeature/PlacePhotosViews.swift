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
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: AppSpacing.sm) {
                    ForEach(photos) { photo in
                        Button {
                            opened = photo
                        } label: {
                            RemotePhoto(path: photo.thumbnailPath, url: urls[photo.thumbnailPath])
                                .frame(width: 150, height: 150)
                                .background(AppColors.bgMuted)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("photo.open"))
                    }
                }
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
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                Picker(selection: $kind) {
                    ForEach(PlacePhotoKind.allCases) { option in
                        Text(LocalizedStringKey(option.titleKey)).tag(option)
                    }
                } label: {
                    Text("place.photos.title")
                }
                .pickerStyle(.segmented)
                .screenPadding()

                if gallery.isEmpty {
                    if isLoading {
                        ProgressView()
                            .padding(.top, AppSpacing.xl)
                    } else {
                        EmptyState(
                            icon: loadError == nil ? "photo.on.rectangle" : "wifi.slash",
                            title: String(localized: "place.photos.empty.title"),
                            description: loadError ?? String(localized: "place.photos.empty.description")
                        )
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(gallery) { photo in
                            Button {
                                opened = photo
                            } label: {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        RemotePhoto(path: photo.thumbnailPath, url: urls[photo.thumbnailPath])
                                    }
                                    .background(AppColors.bgMuted)
                                    .clipped()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("photo.open"))
                            .onAppear {
                                if photo.id == gallery.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }
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
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID

    init(photos: [PlaceGalleryPhoto], urls: [String: URL], selection: UUID, environment: AppEnvironment) {
        self.photos = photos
        self.urls = urls
        self.environment = environment
        _selection = State(initialValue: selection)
    }

    private var current: PlaceGalleryPhoto? { photos.first { $0.id == selection } }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(photos) { photo in
                    RemotePhoto(
                        path: photo.path,
                        url: urls[photo.path],
                        contentMode: .fit,
                        placeholderPath: photo.thumbnailPath
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black)
            .overlay(alignment: .bottom) {
                if let photo = current {
                    caption(photo)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close", systemImage: "xmark") { dismiss() }
                }
                if case .visitor(let photo) = current, !photo.isOwn {
                    ToolbarItem(placement: .topBarTrailing) {
                        // Жалоба — на отчёт с этим фото; блокировка — автора.
                        ModerationMenu(target: .checkin, targetID: photo.checkinID, author: photo.author, isToolbar: true) {
                            dismiss()
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func caption(_ item: PlaceGalleryPhoto) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
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
            if photos.count > 1, let index = photos.firstIndex(where: { $0.id == item.id }) {
                Text(verbatim: "\(index + 1) / \(photos.count)")
                    .font(AppTypography.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(.black.opacity(0.45))
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
