import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import Persistence
import SwiftUI
import Sync
import UIKit

/// Карточка места (RPC `place_card`): тип, название, видимость, описание, автор, маршрут,
/// «Я здесь», свежие отчёты (RPC `place_reports`) со сводкой за 7 дней и «респектом», «Информация»,
/// а у публичных мест — отзывы и обсуждения; внизу — похожие места рядом. Своё место можно изменить,
/// к чужому публичному — предложить правку. Без сети — сохранённая карточка и отчёты,
/// а свои чекины из очереди — с пометкой «Ожидает отправки».
struct PlaceCardView: View {
    let placeID: UUID
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @Environment(SpeciesStore.self) private var speciesStore
    @Environment(SyncEngine.self) private var sync
    @Environment(ReactionStore.self) private var reactions
    @Environment(RulesStore.self) private var rules
    @Environment(PlacesStore.self) private var places: PlacesStore?
    @State private var state: LoadState = .loading
    @State private var reports: [PlaceReport] = []
    /// Смотритель и рекорды — только у публичных мест (сервер для остальных отдаёт пусто).
    @State private var steward: PlaceSteward?
    @State private var records: [PlaceRecord] = []
    /// Подписанные ссылки на фото отчётов: путь в хранилище → ссылка (действует час).
    @State private var photoURLs: [String: URL] = [:]
    /// Фото посетителей для шапки (первые 12).
    @State private var placePhotos: [PlacePhoto] = []
    /// Фото редакции — первыми в шапке.
    @State private var editorialPhotos: [EditorialPhoto] = []
    @State private var showsCheckin = false
    /// Показана сохранённая копия — сервер недоступен.
    @State private var isShowingSavedCopy = false
    @State private var showsEdit = false
    @State private var suggestion: PlaceSuggestionKind?
    /// Мои предложения к месту, которые ещё на проверке.
    @State private var pendingSuggestions: Set<PlaceSuggestionKind> = []
    /// Место из «Рядом» — открывается поверх карточки.
    @State private var nearbySelection: PlaceSelection?
    /// Картинка места для Stories и Telegram.
    @State private var showsShareCard = false
    /// Выбранная вкладка карточки (`nil` — по умолчанию: отчёты или информация).
    @State private var selectedTab: PlaceTab?
    /// Высота листа: открывается наполовину, выбор вкладки раскрывает до полной — содержимое
    /// вкладки не оказывается под краем экрана.
    @State private var detent: PresentationDetent = .medium
    @State private var confirmsDeletePlace = false
    /// Свой отчёт, который просят удалить.
    @State private var reportToDelete: PlaceReport?
    @State private var reportToEdit: ReportEdit?
    @State private var ownActionError: String?

    @Environment(\.dismiss) private var dismiss

    /// Отчётов загружаем больше, чем показываем, — для сводки за 7 дней.
    private static let reportsLimit = 50
    private static let reportsShown = 20

    private var backend: BackendClient? { environment.backend }
    private var cache: CacheStore { environment.cache }
    private var viewerID: UUID? { session.profile?.id }

    enum LoadState {
        case loading
        case loaded(PlaceDetails)
        case notFound
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        SkeletonView(height: 24, width: 200)
                        SkeletonView(height: 14, width: 120)
                        SkeletonView(height: 14)
                        SkeletonView(height: 14, width: 240)
                    }
                    .screenPadding()
                    .padding(.top, AppSpacing.lg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .skeletonLoadingLabel()
                case .loaded(let place):
                    content(place)
                case .notFound:
                    EmptyStateView(
                        icon: "mappin.slash",
                        title: String(localized: "place.card.notFound.title"),
                        description: String(localized: "place.card.notFound.description")
                    )
                case .failed(let message):
                    EmptyStateView(
                        icon: "wifi.slash",
                        title: String(localized: "place.card.failed"),
                        description: message,
                        actionTitle: String(localized: "common.retry"),
                        action: { Task { await load() } },
                        style: .error
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Поделиться ссылкой на место (приватное — некому) или картинкой (только публичное).
                if case .loaded(let place) = state, place.visibility != .private {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            // Публичное — страница в браузере (с превью), для друзей — ссылка в приложение.
                            ShareLink(
                                item: place.visibility == .public && place.status == .published
                                    ? WebLink.place(place.id)
                                    : PlaceLink.url(placeID: place.id),
                                subject: Text(verbatim: place.name),
                                message: shareMessage(place)
                            ) {
                                Label("place.share.link", systemImage: "link")
                            }
                            if place.visibility == .public, place.status == .published {
                                Button("share.title", systemImage: "photo") {
                                    showsShareCard = true
                                }
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .accessibilityLabel(Text("place.share"))
                        }
                    }
                }
                // Своё место: изменить или удалить.
                if case .loaded(let place) = state, place.isOwn, !isShowingSavedCopy {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("place.edit.title", systemImage: "pencil") {
                                showsEdit = true
                            }
                            Button("place.delete", systemImage: "trash", role: .destructive) {
                                confirmsDeletePlace = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .accessibilityLabel(Text("place.ownMenu"))
                        }
                    }
                }
                // Сохранить место (закладка) — после входа.
                if case .loaded(let place) = state, session.profile != nil, !place.isOwn {
                    ToolbarItem(placement: .topBarTrailing) {
                        SavePlaceButton(placeID: place.id, environment: environment)
                    }
                }
                // Чужое место: пожаловаться или заблокировать автора (место тогда пропадёт).
                // Редакцию не блокируют — только жалоба.
                if case .loaded(let place) = state, !place.isOwn {
                    ToolbarItem(placement: .topBarTrailing) {
                        ModerationMenu(
                            target: .place,
                            targetID: place.id,
                            author: place.isEditorial
                                ? nil
                                : FeedAuthor(id: place.ownerID, username: place.ownerUsername, displayName: nil),
                            isToolbar: true
                        ) {
                            Task { await load() }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .task { await load() }
        .task { await speciesStore.loadIfNeeded() }
        // Чекин из очереди принят сервером — он появится среди обычных отчётов.
        .onChange(of: sync.sentCount) { _, _ in
            Task { await loadReports() }
        }
        .sheet(isPresented: $showsCheckin) {
            if case .loaded(let place) = state {
                CheckinFormView(
                    placeID: place.id,
                    placeName: place.name,
                    coordinate: place.coordinate,
                    records: session.profile.map { RecordsLoader(environment: environment, userID: $0.id) },
                    weatherCache: environment.cache
                ) {}
                    .environment(speciesStore)
                    .environment(sync)
                    .environment(rules)
            }
        }
        .confirmationDialog("place.delete.confirm", isPresented: $confirmsDeletePlace, titleVisibility: .visible) {
            Button("place.delete", role: .destructive) {
                Task { await deletePlace() }
            }
        } message: {
            Text("place.delete.message")
        }
        .confirmationDialog(
            "report.delete.confirm",
            isPresented: Binding(get: { reportToDelete != nil }, set: { if !$0 { reportToDelete = nil } }),
            titleVisibility: .visible,
            presenting: reportToDelete
        ) { report in
            Button("report.delete", role: .destructive) {
                Task { await deleteReport(report) }
            }
        } message: { _ in
            Text("report.delete.message")
        }
        .alert(
            "own.error.title",
            isPresented: Binding(get: { ownActionError != nil }, set: { if !$0 { ownActionError = nil } })
        ) {
            Button("common.ok") {}
        } message: {
            Text(verbatim: ownActionError ?? "")
        }
        .sheet(isPresented: $showsEdit) {
            PlaceEditView(placeID: placeID, environment: environment) {
                Task { await load() }
            }
            .environment(speciesStore)
        }
        .sheet(item: $suggestion, onDismiss: { Task { await loadSuggestions() } }) { kind in
            if case .loaded(let place) = state {
                PlaceSuggestView(place: place, kind: kind, environment: environment)
                    .environment(speciesStore)
            }
        }
        .sheet(item: $reportToEdit) { edit in
            ReportEditView(edit: edit, placeName: loadedPlaceName, environment: environment) {
                Task { await loadReports() }
            }
        }
        .sheet(item: $nearbySelection) { selection in
            PlaceCardView(placeID: selection.id, environment: environment)
                .environment(session)
                .environment(speciesStore)
                .environment(sync)
                .environment(reactions)
                .environment(rules)
                .environment(places)
        }
        .sheet(isPresented: $showsShareCard) {
            if case .loaded(let place) = state {
                ShareCardSheet(
                    load: { await placeShareCard(place) },
                    message: { _ in String(localized: "share.message.place \(place.name) \(ShareCardLink.site.absoluteString)") }
                ) { card, format in
                    PlaceShareCardView(card: card, format: format)
                }
            }
        }
    }

    /// Текст к ссылке: название, а у чужого публичного места с точной точкой — и ссылка на карту
    /// для тех, у кого нет приложения.
    /// Данные для картинки места: первое фото посетителей и оценка.
    private func placeShareCard(_ place: PlaceDetails) async -> PlaceShareCard {
        var photo: UIImage?
        if let first = placePhotos.first {
            if let cached = PhotoCache.shared.cached(first.path) {
                photo = cached
            } else if let url = photoURLs[first.path] {
                photo = await PhotoCache.shared.image(path: first.path, url: url)
            }
        }
        let summary = try? await backend?.reviewSummary(place.id)
        return PlaceShareCard(
            name: place.name,
            type: place.type,
            rating: summary?.ratingAverage,
            reviewsCount: summary?.reviewsCount ?? 0,
            photo: photo
        )
    }

    private func shareMessage(_ place: PlaceDetails) -> Text {
        if let map = PlaceLink.mapURL(for: place) {
            Text("place.share.messageWithMap \(place.name) \(map.absoluteString)")
        } else {
            Text("place.share.message \(place.name)")
        }
    }

    private func content(_ place: PlaceDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if !(placePhotos.isEmpty && editorialPhotos.isEmpty) && !isShowingSavedCopy {
                    PlacePhotosHeader(
                        photos: PlaceGalleryPhoto.gallery(editorial: editorialPhotos, visitors: placePhotos),
                        urls: photoURLs,
                        placeID: place.id,
                        placeName: place.name,
                        environment: environment
                    )
                }
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Label(LocalizedStringKey(place.type.titleKey), systemImage: place.type.systemImage)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                    Text(verbatim: place.name)
                        .font(AppTypography.h3)
                }

                HStack(spacing: AppSpacing.sm) {
                    Label(LocalizedStringKey(place.visibility.titleKey), systemImage: place.visibility.systemImage)
                    if place.status == .pending {
                        Label("place.status.pending", systemImage: "hourglass")
                            .foregroundStyle(AppColors.warning)
                    }
                    if place.isApproximate {
                        Label("place.card.approximateShort", systemImage: "circle.dashed")
                    }
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)

                if isShowingSavedCopy {
                    Label("offline.savedCopy", systemImage: "icloud.slash")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                HStack(spacing: AppSpacing.md) {
                    if session.profile != nil {
                        Button {
                            showsCheckin = true
                        } label: {
                            Label("place.card.checkin", systemImage: "mappin.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .primaryButton()
                    }
                    if let destination = routeDestination(place) {
                        RouteButton(destination: destination)
                    }
                }

                // Погода у места: строка, подробно — по нажатию (без сети — сохранённый прогноз).
                PlaceWeatherRow(coordinate: place.coordinate, environment: environment)

                // Запреты и промысловая мера в этой точке (работает без сети) — всегда на виду.
                PlaceRulesSection(coordinate: place.coordinate, environment: environment)
                PlaceParksSection(coordinate: place.coordinate)

                // Остальное — по вкладкам: отчёты, отзывы, обсуждения, информация.
                tabPicker(place)
                tabContent(place)

                if !isShowingSavedCopy {
                    NearbyPlacesSection(place: place, environment: environment) { id in
                        nearbySelection = PlaceSelection(id: id)
                    }
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
        }
    }

    // MARK: - Вкладки

    /// Вкладки карточки: что видно у места. Отзывы и обсуждения — только у публичных опубликованных.
    enum PlaceTab: String, CaseIterable, Identifiable {
        case reports
        case reviews
        case threads
        /// Непубличное место: заметки (у «только я» — дневник, у «друзья» — разговор с друзьями).
        case notes
        case info

        var id: String { rawValue }

        var titleKey: String.LocalizationValue {
            switch self {
            case .reports: "place.tab.reports"
            case .reviews: "reviews.title"
            case .threads: "threads.title"
            case .notes: "place.tab.notes"
            case .info: "place.info.title"
            }
        }

        var systemImage: String {
            switch self {
            case .reports: "clock"
            case .reviews: "star.bubble"
            case .threads: "bubble.left.and.bubble.right"
            case .notes: "note.text"
            case .info: "info.circle"
            }
        }

        /// Что это — одной строкой под вкладками (чем отчёт отличается от отзыва и обсуждения).
        var hintKey: String.LocalizationValue? {
            switch self {
            case .reports: "place.tab.reports.hint"
            case .reviews: "place.tab.reviews.hint"
            case .threads: "place.tab.threads.hint"
            case .notes, .info: nil
            }
        }
    }

    private func tabs(_ place: PlaceDetails) -> [PlaceTab] {
        var tabs: [PlaceTab] = [.reports]
        if place.visibility == .public && place.status == .published && !isShowingSavedCopy {
            tabs += [.reviews, .threads]
        } else if place.visibility != .public && !isShowingSavedCopy && session.profile != nil {
            tabs.append(.notes)
        }
        tabs.append(.info)
        return tabs
    }

    /// Выбранная вкладка; пока не выбирали — отчёты, а если их нет — информация.
    private func currentTab(_ place: PlaceDetails) -> PlaceTab {
        if let selectedTab, tabs(place).contains(selectedTab) { return selectedTab }
        return reports.isEmpty && pendingHere.isEmpty ? .info : .reports
    }

    private func tabLabel(_ tab: PlaceTab) -> String {
        let title = String(localized: tab.titleKey)
        guard tab == .reports, !reports.isEmpty else { return title }
        let count = reports.count >= Self.reportsLimit ? "\(Self.reportsLimit)+" : "\(reports.count)"
        return title + " · " + count
    }

    private func tabPicker(_ place: PlaceDetails) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ChipPicker(
                options: tabs(place),
                selection: Binding(
                    get: { Optional(currentTab(place)) },
                    set: {
                        if let tab = $0 { selectedTab = tab }
                        detent = .large
                    }
                ),
                systemImage: { $0.systemImage },
                label: { tabLabel($0) }
            )
            if let hint = currentTab(place).hintKey {
                Text(String(localized: hint))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            } else if currentTab(place) == .notes {
                // Кто увидит заметки — по видимости места.
                Text(LocalizedStringKey(place.visibility == .private ? "place.tab.notes.hint.private" : "place.tab.notes.hint.friends"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ place: PlaceDetails) -> some View {
        switch currentTab(place) {
        case .reports:
            reportsSection
        case .reviews:
            PlaceReviewsSection(place: place, environment: environment, showsHeader: false)
        case .threads:
            PlaceThreadsSection(place: place, environment: environment, showsHeader: false)
        case .notes:
            PlaceNotesSection(placeID: place.id)
        case .info:
            infoTab(place)
        }
    }

    /// «Информация»: описание, точность точки, атрибуты (правка — у своего, предложение — у чужого),
    /// автор и источник.
    private func infoTab(_ place: PlaceDetails) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            if let description = place.description {
                ExpandableText(description, lineLimit: 8)
            }
            if place.isApproximate {
                RecommendationBox(
                    text: String(localized: "place.card.approximate"),
                    color: AppColors.accent,
                    icon: "circle.dashed"
                )
            }
            PlaceInfoSection(
                place: place,
                canEdit: place.isOwn && !isShowingSavedCopy,
                canSuggest: canSuggest(place),
                pendingSuggestions: pendingSuggestions,
                onEdit: { showsEdit = true },
                onSuggest: { suggestion = $0 },
                showsHeader: false
            )
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                if place.isEditorial {
                    Label("place.card.editorial", systemImage: "checkmark.seal")
                        .foregroundStyle(AppColors.textSecondary)
                } else if let username = place.ownerUsername, !place.isOwn {
                    Text("place.card.addedBy \(username)")
                        .foregroundStyle(AppColors.textTertiary)
                }
                if place.source == .osm {
                    Text("place.card.osm")
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .font(AppTypography.caption)
        }
    }

    @ViewBuilder
    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if let summary = PlaceReportsSummary.make(reports, limit: Self.reportsLimit) {
                PlaceReportsSummaryView(summary: summary)
            }
            if let steward, !isShowingSavedCopy {
                PlaceStewardRow(steward: steward, environment: environment)
            }
            if !records.isEmpty && !isShowingSavedCopy {
                PlaceRecordsView(records: records, photoURLs: photoURLs)
            }
            ForEach(pendingHere) { item in
                PendingReportRow(item: item)
            }
            if reports.isEmpty && pendingHere.isEmpty {
                // Пусто — сразу и что делать: «Я здесь» (после входа и не у сохранённой копии).
                EmptyStateView(
                    icon: "mappin.circle",
                    title: String(localized: "place.card.reports.empty.title"),
                    description: String(localized: "place.card.reports.empty"),
                    actionTitle: session.profile != nil && !isShowingSavedCopy
                        ? String(localized: "place.card.checkin") : nil,
                    action: { showsCheckin = true }
                )
            } else {
                ForEach(reports.prefix(Self.reportsShown)) { report in
                    ReportRow(
                        report: report,
                        photoURLs: photoURLs,
                        isSteward: report.authorID == steward?.userID,
                        onBlocked: { blocked in
                            reports.removeAll { $0.authorID == blocked }
                        },
                        onEdit: editAction(for: report),
                        onDelete: deleteAction(for: report)
                    )
                }
            }
        }
    }

    /// Предложить правку или сообщить о проблеме — к чужому публичному месту, после входа.
    private func canSuggest(_ place: PlaceDetails) -> Bool {
        session.profile != nil && !place.isOwn && place.visibility == .public && place.status == .published
            && !isShowingSavedCopy
    }

    /// Свои чекины в этом месте, ещё не принятые сервером.
    private var pendingHere: [PendingCheckin] {
        sync.pending.filter { $0.placeID == placeID }
    }

    /// Куда строить маршрут: точка подъезда, иначе само место. Для огрублённого места без точки
    /// подъезда маршрут не строим — иначе раскрыли бы примерную точку как точную.
    private func routeDestination(_ place: PlaceDetails) -> GeoPoint? {
        if let access = place.accessPoint { return access }
        return place.isApproximate ? nil : place.coordinate
    }

    private func load() async {
        guard let backend else {
            state = .failed(String(localized: "backend.status.notConfigured"))
            return
        }
        state = .loading
        let key = CacheKey.place(placeID, viewer: viewerID)
        do {
            if let place = try await backend.placeDetails(id: placeID) {
                state = .loaded(place)
                isShowingSavedCopy = false
                try? await cache.save(place, for: key)
                await loadReports()
                await loadSuggestions()
            } else {
                state = .notFound
            }
        } catch {
            // Нет сети — показываем сохранённую карточку: из неё можно отметиться.
            if let saved = try? await cache.load(PlaceDetails.self, for: key) {
                state = .loaded(saved)
                isShowingSavedCopy = true
                reports = (try? await cache.load([PlaceReport].self, for: .reports(placeID, viewer: viewerID))) ?? []
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func loadReports() async {
        guard let backend,
              let loaded = try? await backend.placeReports(placeID: placeID, limit: Self.reportsLimit)
        else { return }
        let photos = (try? await backend.placePhotos(placeID: placeID, limit: 12)) ?? []
        let editorial = (try? await backend.placeEditorialPhotos(placeID: placeID)) ?? []
        steward = try? await backend.placeSteward(placeID: placeID)
        records = (try? await backend.placeRecords(placeID: placeID)) ?? []
        let paths = loaded.prefix(Self.reportsShown).flatMap { report in report.media.flatMap { [$0.thumbnailPath, $0.path] } }
            + photos.flatMap { [$0.thumbnailPath, $0.path] }
            + editorial.flatMap { [$0.thumbnailPath, $0.path] }
            + records.map(\.photoThumbPath)
        let urls = (try? await backend.signedMediaURLs(paths: paths)) ?? [:]
        photoURLs = urls
        placePhotos = photos
        editorialPhotos = editorial
        reports = loaded
        await reactions.load(loaded.prefix(Self.reportsShown).map { ReactionKey(.checkin, $0.id) })
        try? await cache.save(loaded, for: .reports(placeID, viewer: viewerID))
    }

    /// «Удалить отчёт» — только у своего и не у сохранённой копии (без сети).
    private func deleteAction(for report: PlaceReport) -> (@MainActor () -> Void)? {
        guard report.isOwn, !isShowingSavedCopy else { return nil }
        return { reportToDelete = report }
    }

    /// «Изменить отчёт» — там же, где «Удалить».
    private func editAction(for report: PlaceReport) -> (@MainActor () -> Void)? {
        guard report.isOwn, !isShowingSavedCopy else { return nil }
        return { Task { await startEditing(report) } }
    }

    private var loadedPlaceName: String {
        guard case .loaded(let place) = state else { return "" }
        return place.name
    }

    /// Свежая версия своего отчёта с сервера — в форму правки.
    private func startEditing(_ report: PlaceReport) async {
        guard let backend else {
            ownActionError = String(localized: "own.error.offline")
            return
        }
        do {
            if let edit = try await backend.ownReport(report.id) {
                reportToEdit = edit
            } else {
                await loadReports()
            }
        } catch {
            ownActionError = String(localized: "own.error.offline")
        }
    }

    private func deletePlace() async {
        guard let backend else {
            ownActionError = String(localized: "own.error.offline")
            return
        }
        do {
            try await backend.deletePlace(placeID)
            try? await cache.remove(.place(placeID, viewer: viewerID))
            NotificationCenter.default.post(name: .daladaPlaceDeleted, object: placeID)
            dismiss()
        } catch {
            ownActionError = error.localizedDescription
        }
    }

    private func deleteReport(_ report: PlaceReport) async {
        guard let backend else {
            ownActionError = String(localized: "own.error.offline")
            return
        }
        do {
            try await backend.deleteReport(report.id)
            reports.removeAll { $0.id == report.id }
            await loadReports()
        } catch {
            ownActionError = error.localizedDescription
        }
    }

    /// Мои открытые предложения к месту — чтобы показать «на проверке».
    private func loadSuggestions() async {
        guard let backend, case .loaded(let place) = state, canSuggest(place),
              let open = try? await backend.openPlaceSuggestions(placeID: place.id)
        else { return }
        pendingSuggestions = open
    }
}

/// Отчёт в карточке места: автор, время, подтверждение, условия, заметка, уловы, фото.
struct ReportRow: View {
    let report: PlaceReport
    let photoURLs: [String: URL]
    /// Автор — смотритель места: звёздочка у имени.
    var isSteward = false
    /// Автора заблокировали — убрать его отчёты с экрана.
    var onBlocked: (@MainActor (UUID) -> Void)?
    /// Свой отчёт: «Изменить отчёт».
    var onEdit: (@MainActor () -> Void)?
    /// Свой отчёт: «Удалить отчёт» (подтверждение — у вызывающего).
    var onDelete: (@MainActor () -> Void)?

    @Environment(SpeciesStore.self) private var speciesStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                Text(verbatim: author)
                    .font(AppTypography.bodyEmphasis)
                if isSteward {
                    Image(systemName: "star.circle.fill")
                        .foregroundStyle(AppColors.accent)
                        .accessibilityLabel(Text("steward.title"))
                }
                if report.verified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppColors.success)
                        .accessibilityLabel(Text("report.verified"))
                }
                Spacer(minLength: 0)
                Text(report.at, style: .relative)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                if report.isOwn, onEdit != nil || onDelete != nil {
                    Menu {
                        if let onEdit {
                            Button("report.edit", systemImage: "pencil", action: onEdit)
                        }
                        if let onDelete {
                            Button("report.delete", systemImage: "trash", role: .destructive, action: onDelete)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                            .accessibilityLabel(Text("report.ownMenu"))
                    }
                }
                if !report.isOwn {
                    ModerationMenu(
                        target: .checkin,
                        targetID: report.id,
                        author: FeedAuthor(id: report.authorID, username: report.authorUsername, displayName: report.authorDisplayName)
                    ) {
                        onBlocked?(report.authorID)
                    }
                }
            }

            if let conditionsText {
                Text(verbatim: conditionsText)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            if let note = report.note {
                Text(verbatim: note)
                    .font(AppTypography.bodySmall)
            }

            ForEach(report.catches) { item in
                CatchSummaryRow(
                    speciesName: speciesStore.name(for: item.speciesID),
                    count: item.count,
                    weightGrams: item.weightGrams,
                    lengthMillimeters: item.lengthMillimeters,
                    released: item.released
                )
            }

            if !report.media.isEmpty {
                ReportPhotoStrip(media: report.media, urls: photoURLs)
            }

            HStack(spacing: AppSpacing.lg) {
                ReactionButton(key: ReactionKey(.checkin, report.id), isOwn: report.isOwn)
                CommentsButton(key: ReactionKey(.checkin, report.id))
            }
        }
        .cardContentPadding()
        .cardStyle()
    }

    private var author: String {
        if report.isOwn { return String(localized: "report.you") }
        if let username = report.authorUsername { return "@" + username }
        return report.authorDisplayName ?? String(localized: "profile.noName")
    }

    private var conditionsText: String? {
        ConditionsText.make(report.conditions)
    }
}

/// Заметки непубличного места: сколько и «Открыть» (комментарии к месту).
struct PlaceNotesSection: View {
    let placeID: UUID

    @Environment(ReactionStore.self) private var reactions

    var body: some View {
        let key = ReactionKey(.place, placeID)
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if reactions.commentCount(for: key) == 0 {
                Text("place.notes.empty")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
            CommentsButton(key: key, isProminent: true)
        }
        .task(id: placeID) { await reactions.loadCommentCounts([key]) }
    }
}

