import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

/// «Слои карты» — лист вместо разросшегося меню: места (свои, остальные, типы чипами) и то, что
/// поверх карты (запреты, нацпарки и заповедники, погранзона, мои треки после входа). Настройки —
/// те же `@AppStorage`, что читает карта, поэтому она меняется сразу, пока лист открыт.
struct MapLayersSheet: View {
    let isSignedIn: Bool

    @Environment(\.dismiss) private var dismiss
    @AppStorage("map.showsRules") private var showsRules = true
    @AppStorage("map.showsParks") private var showsParks = true
    @AppStorage("map.showsBorder") private var showsBorder = false
    @AppStorage("map.showsTracks") private var showsTracks = false
    @AppStorage("map.showsOwnPlaces") private var showsOwnPlaces = true
    @AppStorage("map.showsOtherPlaces") private var showsOtherPlaces = true
    @AppStorage("map.hiddenTypes") private var hiddenTypesStorage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("map.layers.places") {
                    Toggle(isOn: $showsOwnPlaces) {
                        Label("map.layers.ownPlaces", systemImage: "person.crop.circle")
                    }
                    Toggle(isOn: $showsOtherPlaces) {
                        Label("map.layers.otherPlaces", systemImage: "mappin.and.ellipse")
                    }
                    ChipPicker(
                        String(localized: "map.layers.types"),
                        options: PlaceType.allCases,
                        selection: shownTypes,
                        systemImage: { $0.systemImage },
                        label: { String(localized: String.LocalizationValue($0.titleKey)) }
                    )
                    if !hiddenTypesStorage.isEmpty {
                        Button("map.layers.allTypes", systemImage: "checklist.checked") {
                            hiddenTypesStorage = ""
                        }
                    }
                }
                Section("map.layers.overlays") {
                    Toggle(isOn: $showsRules) {
                        Label("map.rules", systemImage: "exclamationmark.shield")
                    }
                    Toggle(isOn: $showsParks) {
                        Label("map.layers.parks", systemImage: "tree")
                    }
                    Toggle(isOn: $showsBorder) {
                        Label("map.layers.border", systemImage: "flag")
                    }
                    if isSignedIn {
                        Toggle(isOn: $showsTracks) {
                            Label("map.layers.tracks", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                    }
                }
            }
            .navigationTitle("map.layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Видимые типы — выбранные чипы; хранятся скрытые, чтобы новые типы были видны сразу.
    private var shownTypes: Binding<Set<PlaceType>> {
        Binding {
            Set(PlaceType.allCases).subtracting(MapPlaceFilter.types(from: hiddenTypesStorage))
        } set: { shown in
            hiddenTypesStorage = MapPlaceFilter.storage(Set(PlaceType.allCases).subtracting(shown))
        }
    }
}
