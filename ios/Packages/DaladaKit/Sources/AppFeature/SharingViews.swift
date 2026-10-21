import Backend
import DaladaCore
import DaladaUI
import DesignComponents
import DesignSupport
import DesignTokens
import MapEngine
import Persistence
import SwiftUI

// MARK: - Профиль другого человека: поездки, места, итоги

/// Поездки, места и итоги человека — то, что я вижу по их видимости.
struct UserContentSections: View {
    let userID: UUID
    let isFriend: Bool
    let environment: AppEnvironment

    @State private var stats: UserPublicStats?
    @State private var trips: [TripSummary] = []
    @State private var places: [PlaceSummary] = []
    @State private var isLoaded = false
    @State private var selectedPlace: PlaceSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            if let stats {
                UserStatsCard(stats: stats)
            }

            if !trips.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    SectionHeader(String(localized: "person.trips")) {
                        NavigationLink {
                            UserTripsListView(userID: userID, environment: environment)
                        } label: {
                            Text("trips.all")
                        }
                    }
                    VStack(spacing: AppSpacing.md) {
                        ForEach(trips.prefix(3)) { trip in
                            NavigationLink {
                                TripDetailView(tripID: trip.id, environment: environment)
                            } label: {
                                TripRow(trip: trip)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .cardContentPadding()
                    .cardStyle()
                }
            }

            if !places.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    SectionHeader(String(localized: "person.places")) {
                        if places.count > 5 {
                            NavigationLink {
                                UserPlacesListView(places: places, environment: environment)
                            } label: {
                                Text("trips.all")
                            }
                        }
                    }
                    VStack(spacing: AppSpacing.md) {
                        ForEach(places.prefix(5)) { place in
                            Button {
                                selectedPlace = PlaceSelection(id: place.id)
                            } label: {
                                PlaceRow(place: place)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .cardContentPadding()
                    .cardStyle()
                }
            }

            if isLoaded && trips.isEmpty && places.isEmpty {
                Text(LocalizedStringKey(isFriend ? "person.nothingShared" : "person.friendsOnlyHint"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .task(id: "\(userID)-\(isFriend)") { await load() }
        .sheet(item: $selectedPlace) { selection in
            PlaceCardView(placeID: selection.id, environment: environment)
        }
    }

    private func load() async {
        defer { isLoaded = true }
        guard let backend = environment.backend else { return }
        async let loadedStats = backend.userStats(userID)
        async let loadedTrips = backend.userTrips(userID, limit: 3)
        async let loadedPlaces = backend.userPlaces(userID)
        stats = try? await loadedStats
        trips = (try? await loadedTrips) ?? []
        places = (try? await loadedPlaces) ?? []
    }
}

/// Итоги человека: поездки, километры, места, уловы.
struct UserStatsCard: View {
    let stats: UserPublicStats

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            StatTile(title: String(localized: "person.stats.trips"), value: "\(stats.tripsCount)")
            StatTile(title: String(localized: "person.stats.distance"), value: TripFormat.distance(Double(stats.distanceM)))
            StatTile(title: String(localized: "person.stats.places"), value: "\(stats.placesCount)")
            StatTile(title: String(localized: "person.stats.catches"), value: "\(stats.catchesCount)")
        }
        .cardContentPadding()
        .cardStyle()
    }
}

/// Все поездки человека, которые я вижу; следующая страница — при прокрутке до конца.
struct UserTripsListView: View {
    let userID: UUID
    let environment: AppEnvironment

    private static let pageSize = 30

    @State private var trips: [TripSummary] = []
    @State private var hasMore = true
    @State private var isLoaded = false
    @State private var isLoadingMore = false
    @State private var loadFailed = false

    var body: some View {
        Group {
            if trips.isEmpty && isLoaded {
                PlaceholderScreen(
                    icon: "figure.hiking",
                    title: String(localized: "person.trips.empty"),
                    description: String(localized: "person.friendsOnlyHint")
                )
            } else {
                List {
                    ForEach(trips) { trip in
                        NavigationLink {
                            TripDetailView(tripID: trip.id, environment: environment)
                        } label: {
                            TripRow(trip: trip)
                        }
                    }
                    // Следующая страница — когда низ списка на экране (DesignKit).
                    LoadMoreFooter(state: loadState, onLoad: loadMore) {
                        TripRowSkeleton()
                    }
                }
            }
        }
        .navigationTitle("person.trips")
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        defer { isLoaded = true }
        guard let backend = environment.backend,
              let page = try? await backend.userTrips(userID, limit: Self.pageSize)
        else { return }
        trips = page
        hasMore = page.count >= Self.pageSize
    }

    private var loadState: LoadMoreState {
        if isLoadingMore { return .loading }
        if loadFailed { return .failed(message: nil) }
        return hasMore && !trips.isEmpty ? .more : .end
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, let backend = environment.backend, let last = trips.last else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await backend.userTrips(userID, limit: Self.pageSize, before: last.startedAt)
            let known = Set(trips.map(\.id))
            trips += page.filter { !known.contains($0.id) }
            hasMore = page.count >= Self.pageSize
            loadFailed = false
        } catch is CancellationError {
            return
        } catch {
            loadFailed = true
        }
    }
}

/// Все места человека, которые я вижу.
struct UserPlacesListView: View {
    let places: [PlaceSummary]
    let environment: AppEnvironment

    @State private var selectedPlace: PlaceSelection?

    var body: some View {
        List(places) { place in
            Button {
                selectedPlace = PlaceSelection(id: place.id)
            } label: {
                PlaceRow(place: place)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("person.places")
        .sheet(item: $selectedPlace) { selection in
            PlaceCardView(placeID: selection.id, environment: environment)
        }
    }
}

// MARK: - Зоны приватности

/// Зоны приватности: другие не видят участки ваших треков рядом с домом, дачей.
struct PrivacyZonesView: View {
    let environment: AppEnvironment

    @State private var zones: [PrivacyZone] = []
    @State private var isLoaded = false
    @State private var loadError: String?
    @State private var editing: EditorRequest?
    @State private var mode: CardListMode = .browsing
    @State private var selection: Set<PrivacyZone.ID> = []
    /// Зоны, удаление которых ждёт подтверждения.
    @State private var pendingDelete: [PrivacyZone] = []

    /// Открытый редактор: новая зона (`zone == nil`) или изменение.
    struct EditorRequest: Identifiable {
        let id = UUID()
        let zone: PrivacyZone?
    }

    var body: some View {
        // DesignKit 8.0.0: зоны — CardList в стеклянной секции; долгое нажатие — «Изменить» и
        // «Удалить», в панели — выбор нескольких и «+» (до этого List со смахиванием).
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if isLoaded && zones.isEmpty && loadError == nil {
                    EmptyState(
                        icon: "house.circle",
                        title: String(localized: "privacyZones.title"),
                        description: String(localized: "privacyZones.explanation"),
                        actionTitle: String(localized: "privacyZones.add"),
                        action: { editing = EditorRequest(zone: nil) }
                    )
                } else {
                    if !zones.isEmpty {
                        CardList(zones, layout: .section, mode: mode, selection: $selection) { zone in
                            zoneRow(zone)
                        }
                    }
                    Text(zones.count >= PrivacyZone.limit
                        ? LocalizedStringKey("privacyZones.limit")
                        : LocalizedStringKey("privacyZones.explanation"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.xs)
                    if let loadError {
                        InlineStatusText(message: loadError, type: .error)
                    }
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle("privacyZones.title")
        .cardListToolbar(
            mode: $mode,
            selection: $selection,
            allIDs: zones.map(\.id),
            canReorder: false,
            addLabel: String(localized: "privacyZones.add"),
            onAdd: canAdd ? { editing = EditorRequest(zone: nil) } : nil,
            onDeleteSelected: { pendingDelete = zones.filter { selection.contains($0.id) } }
        )
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { request in
            PrivacyZoneEditorView(zone: request.zone, environment: environment)
        }
        .confirmationDialog(
            pendingDelete.count == 1
                ? LocalizedStringKey("privacyZones.deleteConfirm")
                : LocalizedStringKey("common.deleteSelectedConfirm \(pendingDelete.count)"),
            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }),
            titleVisibility: .visible
        ) {
            Button("privacyZones.delete", role: .destructive) {
                let removed = pendingDelete
                pendingDelete = []
                selection = []
                mode = .browsing
                Task { await delete(removed) }
            }
        }
    }

    private var canAdd: Bool {
        isLoaded && loadError == nil && zones.count < PrivacyZone.limit
    }

    private func zoneRow(_ zone: PrivacyZone) -> some View {
        Button {
            editing = EditorRequest(zone: zone)
        } label: {
            HStack(spacing: AppSpacing.md) {
                Icon("house.circle.fill", size: AppIconSize.lg)
                    .foregroundStyle(AppColors.accent)
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(verbatim: zone.name)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("privacyZones.radius \(TripFormat.distance(Double(zone.radiusM)))")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Метка кнопки не передаёт отступ разделителя наружу: значок и промежуток после него.
        .rowDividerInset(AppIconSize.lg + AppSpacing.md)
        .contextMenu {
            Button("common.edit", systemImage: "pencil") {
                editing = EditorRequest(zone: zone)
            }
            Button("common.delete", systemImage: "trash", role: .destructive) {
                pendingDelete = [zone]
            }
        }
    }

    private func load() async {
        defer { isLoaded = true }
        guard let backend = environment.backend else {
            loadError = String(localized: "backend.status.notConfigured")
            return
        }
        do {
            zones = try await backend.privacyZones()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func delete(_ removed: [PrivacyZone]) async {
        guard let backend = environment.backend else { return }
        for zone in removed {
            try? await backend.deletePrivacyZone(zone.id)
        }
        await load()
    }
}

/// Новая или изменённая зона: центр — перекрестье карты, радиус 200–1000 м, название.
struct PrivacyZoneEditorView: View {
    let zone: PrivacyZone?
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PrivacyZoneDraft?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var confirmsDelete = false

    private static let suggestions = ["privacyZones.suggestion.home", "privacyZones.suggestion.dacha", "privacyZones.suggestion.work"]

    var body: some View {
        EditSheetContainer(
            title: String(localized: String.LocalizationValue(zone == nil ? "privacyZones.new" : "privacyZones.edit")),
            isSaveDisabled: !(draft?.isValid ?? false),
            isSaving: isSaving,
            wrapInForm: false,
            onSave: { Task { await save() } },
            onCancel: { dismiss() }
        ) {
            Group {
                if let binding = Binding($draft) {
                    editor(binding)
                        .transition(.skeletonReveal)
                } else {
                    // Ищем, где вы сейчас: скелетон карты и полей.
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            Skeleton(height: 300, cornerRadius: AppRadius.xl)
                            SkeletonText(AppTypography.caption, lines: 2)
                            Skeleton(height: 48, cornerRadius: AppRadius.xl)
                        }
                        .shimmer()
                        .skeletonLoadingLabel()
                        .screenPadding()
                        .padding(.vertical, AppSpacing.lg)
                    }
                    .scrollDisabled(true)
                    .transition(.opacity)
                }
            }
            // Нашли, где вы, — карта и поля проявляются на месте скелетона.
            .animation(AppAnimation.smooth, value: draft == nil)
        }
        .confirmationDialog("privacyZones.deleteConfirm", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("privacyZones.delete", role: .destructive) {
                Task { await delete() }
            }
        }
        .task {
            guard draft == nil else { return }
            if let zone {
                draft = PrivacyZoneDraft(editing: zone)
            } else {
                draft = PrivacyZoneDraft(center: await DeviceLocation.current(timeout: .seconds(5)) ?? .almaty)
            }
        }
    }

    private func editor(_ draft: Binding<PrivacyZoneDraft>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    ZStack {
                        DaladaMapView(
                            styleURL: environment.config.mapStyleURL,
                            initialCenter: draft.wrappedValue.center,
                            initialZoom: 14,
                            places: [
                                MapPlace(
                                    id: draft.wrappedValue.id,
                                    coordinate: draft.wrappedValue.center,
                                    isOwn: true,
                                    approximateRadiusM: draft.wrappedValue.radiusM
                                ),
                            ],
                            onRegionChange: { box in draft.wrappedValue.center = box.center }
                        )
                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .light)) // design-lint:ignore прицел поверх карты, не растёт с текстом
                            .foregroundStyle(AppColors.textPrimary)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl))

                    Text("privacyZones.editor.hint")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.horizontal, AppSpacing.lg)
                }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    FormSection {
                        FormTextField(text: draft.name, placeholder: String(localized: "privacyZones.name"), style: .row)
                    }
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(Self.suggestions, id: \.self) { key in
                            DSButton(
                                String(localized: String.LocalizationValue(key)),
                                appearance: .secondary,
                                size: .small
                            ) {
                                draft.wrappedValue.name = String(localized: String.LocalizationValue(key))
                            }
                        }
                    }
                }

                FormSection(footer: String(localized: "privacyZones.radiusHint")) {
                    // Строка со слайдером DesignKit, как в Tenra: щелчок на каждом шаге.
                    UniversalRow(
                        String(localized: "privacyZones.radiusTitle"),
                        accessory: .slider(
                            Binding(
                                get: { Double(draft.wrappedValue.radiusM) },
                                set: { draft.wrappedValue.radiusM = Int($0.rounded()) }
                            ),
                            in: Double(PrivacyZone.radiusRange.lowerBound)...Double(PrivacyZone.radiusRange.upperBound),
                            step: Double(PrivacyZone.radiusStep),
                            valueText: TripFormat.distance(Double(draft.wrappedValue.radiusM))
                        )
                    )
                }

                if let saveError {
                    InlineStatusText(message: saveError, type: .error)
                }

                if zone != nil {
                    FormSection {
                        UniversalRow(
                            String(localized: "privacyZones.delete"),
                            role: .destructive,
                            accessory: .action {
                                confirmsDelete = true
                            }
                        )
                    }
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
        }
    }

    private func save() async {
        guard let draft, draft.isValid, let backend = environment.backend else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await backend.savePrivacyZone(draft)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func delete() async {
        guard let zone, let backend = environment.backend else { return }
        do {
            try await backend.deletePrivacyZone(zone.id)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
