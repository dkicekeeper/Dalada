import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import Persistence
import SwiftUI
import Sync

/// Свои фото: сеть, без неё — сохранённая первая страница.
struct MyPhotosLoader {
    let environment: AppEnvironment
    let userID: UUID

    static let pageSize = 60

    func firstPage() async -> [MyPhoto] {
        let key = CacheKey.myPhotos(userID)
        if let backend = environment.backend, let loaded = try? await backend.myPhotos(limit: Self.pageSize) {
            try? await environment.cache.save(loaded, for: key)
            return loaded
        }
        return (try? await environment.cache.load([MyPhoto].self, for: key)) ?? []
    }
}

/// «Фото» в профиле: сетка последних 6, «Все» — все фото по месяцам. Нажатие — на весь экран.
struct MyPhotosSection: View {
    let environment: AppEnvironment
    let userID: UUID
    var showsTitle = true

    @Environment(SyncEngine.self) private var sync
    @State private var photos: [MyPhoto] = []
    @State private var urls: [String: URL] = [:]
    @State private var isLoaded = false
    @State private var opened: MyPhoto?

    var body: some View {
        ProfileSection("profile.photos.title", systemImage: "photo.on.rectangle", showsAll: photos.count > 6, showsTitle: showsTitle) {
            MyPhotosView(environment: environment, userID: userID)
        } content: {
            if !photos.isEmpty {
                PhotoGrid(photos: Array(photos.prefix(6)), urls: urls) { opened = $0 }
            } else if isLoaded {
                ProfileSectionHint(text: String(localized: "profile.photos.empty"))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .task(id: userID) { await load() }
        // Отчёт с фото дошёл до сервера — показать его фото.
        .onChange(of: sync.sentCount) { _, _ in
            Task { await load() }
        }
        .fullScreenCover(item: $opened) { photo in
            let shown = Array(photos.prefix(6))
            PhotoViewer(media: shown.map(\.reportMedia), urls: urls, selection: photo.id)
        }
    }

    private func load() async {
        photos = await MyPhotosLoader(environment: environment, userID: userID).firstPage()
        isLoaded = true
        await loadURLs(for: Array(photos.prefix(6)))
    }

    private func loadURLs(for shown: [MyPhoto]) async {
        guard let backend = environment.backend, !shown.isEmpty else { return }
        let paths = shown.flatMap { [$0.thumbnailPath, $0.path] }
        urls.merge((try? await backend.signedMediaURLs(paths: paths)) ?? [:]) { _, new in new }
    }
}

/// Все свои фото по месяцам, новые сверху; следующая страница — при прокрутке до конца.
struct MyPhotosView: View {
    let environment: AppEnvironment
    let userID: UUID

    @State private var photos: [MyPhoto] = []
    @State private var urls: [String: URL] = [:]
    @State private var hasMore = true
    @State private var isLoaded = false
    @State private var opened: MyPhoto?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.lg) {
                if photos.isEmpty && isLoaded {
                    EmptyState(
                        icon: "photo.on.rectangle",
                        title: String(localized: "profile.photos.title"),
                        description: String(localized: "profile.photos.empty")
                    )
                }
                ForEach(PhotoMonth.group(photos)) { month in
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text(verbatim: month.id.formatted(.dateTime.month(.wide).year()))
                            .font(AppTypography.bodyEmphasis)
                        PhotoGrid(photos: month.photos, urls: urls) { opened = $0 }
                    }
                }
                if hasMore && !photos.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { await loadMore() }
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
        }
        .navigationTitle(Text("profile.photos.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .fullScreenCover(item: $opened) { photo in
            PhotoViewer(media: photos.map(\.reportMedia), urls: urls, selection: photo.id)
        }
    }

    private func reload() async {
        let page = await MyPhotosLoader(environment: environment, userID: userID).firstPage()
        photos = page
        hasMore = page.count >= MyPhotosLoader.pageSize && environment.backend != nil
        isLoaded = true
        await loadURLs(for: page)
    }

    private func loadMore() async {
        guard hasMore, let backend = environment.backend, let last = photos.last,
              let page = try? await backend.myPhotos(limit: MyPhotosLoader.pageSize, after: last)
        else {
            hasMore = false
            return
        }
        let known = Set(photos.map(\.id))
        photos += page.filter { !known.contains($0.id) }
        hasMore = page.count >= MyPhotosLoader.pageSize
        await loadURLs(for: page)
    }

    private func loadURLs(for page: [MyPhoto]) async {
        guard let backend = environment.backend, !page.isEmpty else { return }
        // На весь экран открываются полные файлы — их ссылки тоже.
        let paths = page.flatMap { [$0.thumbnailPath, $0.path] }
        urls.merge((try? await backend.signedMediaURLs(paths: paths)) ?? [:]) { _, new in new }
    }
}

/// Сетка квадратных превью в три колонки.
struct PhotoGrid: View {
    let photos: [MyPhoto]
    let urls: [String: URL]
    let onOpen: @MainActor (MyPhoto) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: AppSpacing.xs), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.xs) {
            ForEach(photos) { photo in
                Button {
                    onOpen(photo)
                } label: {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            RemotePhoto(path: photo.thumbnailPath, url: urls[photo.thumbnailPath])
                        }
                        .background(AppColors.bgMuted)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: photo.placeName ?? String(localized: "photo.open")))
            }
        }
    }
}
