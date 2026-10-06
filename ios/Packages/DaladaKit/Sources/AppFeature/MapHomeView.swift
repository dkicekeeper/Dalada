import DaladaCore
import DesignTokens
import MapEngine
import SwiftUI

/// Зона правил, открытая с карты — для `.sheet(item:)`.
struct RuleZoneSelection: Identifiable, Hashable {
    let id: String
}

/// Вкладка «Карта»: места в видимой области, карточка по тапу, новое место долгим нажатием
/// или кнопкой «Место», слои — зоны запретов (цвет — действует сейчас, скоро или нет), нацпарки и
/// заповедники, погранзона, мои треки; «Начать поездку».
struct MapHomeView: View {
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @Environment(RulesStore.self) private var rules
    @Environment(TripRecorder.self) private var recorder
    @AppStorage("map.showsRules") private var showsRules = true
    @AppStorage("map.showsParks") private var showsParks = true
    @AppStorage("map.showsBorder") private var showsBorder = false
    @AppStorage("map.showsTracks") private var showsTracks = false
    @AppStorage("map.showsPhotos") private var showsPhotos = false
    @State private var photosLayer: MyPhotosLayer
    @State private var openedPhoto: MyPhotoPoint?
    @AppStorage("map.showsOwnPlaces") private var showsOwnPlaces = true
    @AppStorage("map.showsOtherPlaces") private var showsOtherPlaces = true
    /// Скрытые типы мест: «campsite,base».
    @AppStorage("map.hiddenTypes") private var hiddenTypesStorage = ""
    @State private var model: MapScreenModel
    @State private var tracks: MyTracksLayer
    @State private var showsSignInHint = false
    @State private var selectedZone: RuleZoneSelection?
    /// Нацпарк, заповедник или погранзона, открытые с карты.
    @State private var selectedArea: RuleZoneSelection?
    @State private var showsLayers = false
    /// Подсказка «долгое нажатие — новое место»: показываем, пока человек не поставил место или
    /// не закрыл её.
    @AppStorage("map.longPressHintSeen") private var longPressHintSeen = false
    /// «Где я»: каждое нажатие — новое значение, карта едет к пользователю.
    @State private var locateRequest = 0

    init(environment: AppEnvironment) {
        self.environment = environment
        _model = State(initialValue: MapScreenModel(backend: environment.backend, cache: environment.cache))
        _tracks = State(initialValue: MyTracksLayer(backend: environment.backend, cache: environment.cache))
        _photosLayer = State(initialValue: MyPhotosLayer(backend: environment.backend, cache: environment.cache))
    }

    var body: some View {
        DaladaMapView(
            styleURL: environment.config.mapStyleURL,
            initialCenter: .almaty,
            initialZoom: 8,
            places: model.mapPlaces.filter { placeFilter.includes(type: $0.type, isOwn: $0.isOwn) },
            draftPin: model.newPlace?.coordinate,
            historySegments: showsTracks && session.profile != nil ? tracks.segments : [],
            locateRequest: locateRequest,
            // Слои снизу вверх: погранзона, нацпарки, зоны запретов.
            ruleAreas: rules.mapLayerAreas(parks: showsParks, border: showsBorder) + (showsRules ? rules.mapAreas() : []),
            photos: showsPhotos && session.profile != nil ? photosLayer.mapPhotos : [],
            onRegionChange: { model.visibleAreaChanged($0, viewer: session.profile?.id) },
            onPlaceTap: { model.selectedPlace = PlaceSelection(id: $0) },
            onRuleAreaTap: { id in
                if id.hasPrefix(RulesStore.areaPrefix) {
                    selectedArea = RuleZoneSelection(id: String(id.dropFirst(RulesStore.areaPrefix.count)))
                } else {
                    selectedZone = RuleZoneSelection(id: id)
                }
            },
            onPhotoTap: { openedPhoto = photosLayer.point($0) },
            onLongPress: { startNewPlace(at: $0) }
        )
        // Карта — на весь экран, под панелью вкладок; кнопки поверх — в безопасной области.
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            // Слои карты — листом: места (свои, остальные, типы), запреты, нацпарки и заповедники,
            // погранзона, мои треки (после входа).
            Button {
                showsLayers = true
            } label: {
                // Скрыта часть мест — значок с заливкой.
                Label("map.layers", systemImage: placeFilter.isActive ? "square.3.layers.3d.top.filled" : "square.3.layers.3d")
                    .font(AppTypography.bodyEmphasis)
            }
            .secondaryButton()
            .padding(.leading, AppSpacing.lg)
            .padding(.top, AppSpacing.sm)
        }
        .sheet(isPresented: $showsLayers) {
            MapLayersSheet(isSignedIn: session.profile != nil)
        }
        .sheet(item: $selectedZone) { selection in
            NavigationStack {
                RuleZoneView(zoneID: selection.id, environment: environment)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedArea) { selection in
            NavigationStack {
                MapAreaView(areaID: selection.id)
            }
            .presentationDetents([.medium, .large])
        }
        .task { await rules.loadIfNeeded() }
        // Своё место удалили из карточки — убрать его с карты.
        .onReceive(NotificationCenter.default.publisher(for: .daladaPlaceDeleted)) { _ in
            Task { await model.reload() }
        }
        // Треки — когда слой включён: при включении, смене аккаунта и возвращении на вкладку.
        .task(id: TracksRequest(isOn: showsTracks, userID: session.profile?.id)) {
            if showsTracks { await tracks.load(for: session.profile?.id) }
        }
        .onAppear {
            if showsTracks { Task { await tracks.load(for: session.profile?.id) } }
            if showsPhotos { Task { await photosLayer.load(for: session.profile?.id) } }
        }
        // «Мои фото» — так же, как треки.
        .task(id: TracksRequest(isOn: showsPhotos, userID: session.profile?.id)) {
            if showsPhotos { await photosLayer.load(for: session.profile?.id) }
        }
        .fullScreenCover(item: $openedPhoto) { point in
            MapPhotoViewer(point: point, environment: environment)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                startNewPlace(at: model.visibleCenter)
            } label: {
                Label("map.addPlace", systemImage: "plus")
                    .font(AppTypography.bodyEmphasis)
            }
            .secondaryButton()
            .padding(.trailing, AppSpacing.lg)
            .padding(.top, AppSpacing.sm)
        }
        .overlay(alignment: .top) {
            if !longPressHintSeen && session.profile != nil {
                longPressHint
                    .padding(.top, 64)
                    .screenPadding()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                locateRequest += 1
            } label: {
                Image(systemName: "location")
                    .font(AppTypography.bodyEmphasis)
                    .accessibilityLabel(Text("map.locate"))
            }
            .secondaryButton()
            .buttonBorderShape(.circle)
            .padding(.trailing, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
        }
        // Во время записи вместо кнопки — мини-плеер над вкладками (где он есть).
        .overlay(alignment: .bottom) {
            if !recorder.isActive || !TripAccessoryModifier.isAvailable {
                StartTripButton()
                    .font(AppTypography.bodyEmphasis)
                    .primaryButton()
                    .padding(.bottom, AppSpacing.lg)
            }
        }
        .sheet(item: $model.selectedPlace) { selection in
            PlaceCardView(placeID: selection.id, environment: environment)
        }
        .sheet(item: $model.newPlace) { request in
            PlaceFormView(coordinate: request.coordinate) { draft in
                await model.create(draft)
            }
        }
        .alert("map.signInRequired.title", isPresented: $showsSignInHint) {
            Button("common.ok") {}
        } message: {
            Text("map.signInRequired.message")
        }
    }

    private var placeFilter: MapPlaceFilter {
        MapPlaceFilter(
            showsOwn: showsOwnPlaces,
            showsOthers: showsOtherPlaces,
            hiddenTypes: MapPlaceFilter.types(from: hiddenTypesStorage)
        )
    }

    /// Тип места виден на карте ↔ не в списке скрытых.
    private struct TracksRequest: Equatable {
        let isOn: Bool
        let userID: UUID?
    }

    private func startNewPlace(at coordinate: GeoPoint) {
        guard session.profile != nil else {
            showsSignInHint = true
            return
        }
        longPressHintSeen = true
        model.newPlace = NewPlaceRequest(coordinate: coordinate)
    }

    /// Что место можно поставить долгим нажатием, иначе не узнать: кнопка «Место» ставит его в центр.
    private var longPressHint: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "hand.tap")
                .foregroundStyle(AppColors.accent)
            Text("map.longPressHint")
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                withAnimation { longPressHintSeen = true }
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .accessibilityLabel(Text("common.close"))
            }
            .buttonStyle(.borderless)
        }
        .cardContentPadding()
        .cardStyle()
    }
}
