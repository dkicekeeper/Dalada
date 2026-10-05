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

    init(environment: AppEnvironment) {
        self.environment = environment
        _model = State(initialValue: MapScreenModel(backend: environment.backend, cache: environment.cache))
        _tracks = State(initialValue: MyTracksLayer(backend: environment.backend, cache: environment.cache))
    }

    var body: some View {
        DaladaMapView(
            styleURL: environment.config.mapStyleURL,
            initialCenter: .almaty,
            initialZoom: 8,
            places: model.mapPlaces.filter { placeFilter.includes(type: $0.type, isOwn: $0.isOwn) },
            draftPin: model.newPlace?.coordinate,
            historySegments: showsTracks && session.profile != nil ? tracks.segments : [],
            // Слои снизу вверх: погранзона, нацпарки, зоны запретов.
            ruleAreas: rules.mapLayerAreas(parks: showsParks, border: showsBorder) + (showsRules ? rules.mapAreas() : []),
            onRegionChange: { model.visibleAreaChanged($0, viewer: session.profile?.id) },
            onPlaceTap: { model.selectedPlace = PlaceSelection(id: $0) },
            onRuleAreaTap: { id in
                if id.hasPrefix(RulesStore.areaPrefix) {
                    selectedArea = RuleZoneSelection(id: String(id.dropFirst(RulesStore.areaPrefix.count)))
                } else {
                    selectedZone = RuleZoneSelection(id: id)
                }
            },
            onLongPress: { startNewPlace(at: $0) }
        )
        // Карта — на весь экран, под панелью вкладок; кнопки поверх — в безопасной области.
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            // Слои карты: места (свои, остальные, типы), запреты, нацпарки и заповедники, погранзона,
            // мои треки (после входа).
            Menu {
                Section("map.layers.places") {
                    Toggle(isOn: $showsOwnPlaces) {
                        Label("map.layers.ownPlaces", systemImage: "person.crop.circle")
                    }
                    Toggle(isOn: $showsOtherPlaces) {
                        Label("map.layers.otherPlaces", systemImage: "mappin.and.ellipse")
                    }
                    Menu {
                        ForEach(PlaceType.allCases) { type in
                            Toggle(isOn: typeBinding(type)) {
                                Label(LocalizedStringKey(type.titleKey), systemImage: type.systemImage)
                            }
                        }
                        if !hiddenTypesStorage.isEmpty {
                            Button("map.layers.allTypes", systemImage: "checklist.checked") {
                                hiddenTypesStorage = ""
                            }
                        }
                    } label: {
                        Label("map.layers.types", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                Section {
                    Toggle(isOn: $showsRules) {
                        Label("map.rules", systemImage: "exclamationmark.shield")
                    }
                    Toggle(isOn: $showsParks) {
                        Label("map.layers.parks", systemImage: "tree")
                    }
                    Toggle(isOn: $showsBorder) {
                        Label("map.layers.border", systemImage: "flag")
                    }
                    if session.profile != nil {
                        Toggle(isOn: $showsTracks) {
                            Label("map.layers.tracks", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                    }
                }
            } label: {
                // Скрыта часть мест — значок с заливкой.
                Label("map.layers", systemImage: placeFilter.isActive ? "square.3.layers.3d.top.filled" : "square.3.layers.3d")
                    .font(AppTypography.bodyEmphasis)
            }
            .secondaryButton()
            .padding(.leading, AppSpacing.lg)
            .padding(.top, AppSpacing.sm)
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
                .presentationDetents([.medium, .large])
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
    private func typeBinding(_ type: PlaceType) -> Binding<Bool> {
        Binding {
            !MapPlaceFilter.types(from: hiddenTypesStorage).contains(type)
        } set: { isShown in
            var hidden = MapPlaceFilter.types(from: hiddenTypesStorage)
            if isShown { hidden.remove(type) } else { hidden.insert(type) }
            hiddenTypesStorage = MapPlaceFilter.storage(hidden)
        }
    }

    private struct TracksRequest: Equatable {
        let isOn: Bool
        let userID: UUID?
    }

    private func startNewPlace(at coordinate: GeoPoint) {
        guard session.profile != nil else {
            showsSignInHint = true
            return
        }
        model.newPlace = NewPlaceRequest(coordinate: coordinate)
    }
}
