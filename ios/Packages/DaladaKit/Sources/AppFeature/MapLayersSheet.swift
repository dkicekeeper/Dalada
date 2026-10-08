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
    @AppStorage("map.showsPhotos") private var showsPhotos = false
    @AppStorage("map.showsOwnPlaces") private var showsOwnPlaces = true
    @AppStorage("map.showsOtherPlaces") private var showsOtherPlaces = true
    @AppStorage("map.hiddenTypes") private var hiddenTypesStorage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    FormSection(header: String(localized: "map.layers.places")) {
                        toggle("map.layers.ownPlaces", systemImage: "person.crop.circle", isOn: $showsOwnPlaces)
                        divider
                        toggle("map.layers.otherPlaces", systemImage: "mappin.and.ellipse", isOn: $showsOtherPlaces)
                        divider
                        ChipPicker(
                            String(localized: "map.layers.types"),
                            options: PlaceType.allCases,
                            selection: shownTypes,
                            systemImage: { $0.systemImage },
                            inset: AppSpacing.lg,
                            label: { String(localized: String.LocalizationValue($0.titleKey)) }
                        )
                        .padding(.vertical, AppSpacing.md)
                        if !hiddenTypesStorage.isEmpty {
                            divider
                            ActionSettingsRow(
                                icon: "checklist.checked",
                                title: String(localized: "map.layers.allTypes"),
                                config: .standard
                            ) {
                                hiddenTypesStorage = ""
                            }
                        }
                    }
                    FormSection(header: String(localized: "map.layers.overlays")) {
                        toggle("map.rules", systemImage: "exclamationmark.shield", isOn: $showsRules)
                        divider
                        toggle("map.layers.parks", systemImage: "tree", isOn: $showsParks)
                        divider
                        toggle("map.layers.border", systemImage: "flag", isOn: $showsBorder)
                        if isSignedIn {
                            divider
                            toggle("map.layers.tracks", systemImage: "point.topleft.down.to.point.bottomright.curvepath", isOn: $showsTracks)
                            divider
                            toggle("map.layers.photos", systemImage: "camera", isOn: $showsPhotos)
                        }
                    }
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
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

    private func toggle(_ key: String.LocalizationValue, systemImage: String, isOn: Binding<Bool>) -> some View {
        ToggleSettingsRow(icon: systemImage, title: String(localized: key), config: .standard, isOn: isOn)
    }

    private var divider: some View {
        Divider().padding(.leading, AppSpacing.lg)
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
