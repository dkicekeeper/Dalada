import DesignComponents
import DesignTokens
import SwiftUI

/// Своё в профиле по чипам: поездки, уловы, места, фото. Раньше — четыре раздела подряд, до
/// достижений приходилось листать несколько экранов.
struct ProfileContentTabs: View {
    let environment: AppEnvironment
    let userID: UUID

    @State private var selected: ProfileTab = .trips

    enum ProfileTab: String, CaseIterable, Identifiable {
        case trips
        case catches
        case places
        case photos

        var id: String { rawValue }

        var titleKey: String.LocalizationValue {
            switch self {
            case .trips: "trips.title"
            case .catches: "profile.catches.title"
            case .places: "places.mine.title"
            case .photos: "profile.photos.title"
            }
        }

        var systemImage: String {
            switch self {
            case .trips: "point.topleft.down.to.point.bottomright.curvepath"
            case .catches: "fish"
            case .places: "mappin.and.ellipse"
            case .photos: "photo.on.rectangle"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            ChipPicker(
                options: ProfileTab.allCases,
                // Вкладка выбрана всегда: повторное нажатие на чип её не снимает.
                selection: Binding(
                    get: { Optional(selected) },
                    set: { if let tab = $0 { selected = tab } }
                ),
                systemImage: { $0.systemImage },
                label: { String(localized: $0.titleKey) }
            )
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selected {
        case .trips:
            MyTripsSection(environment: environment, userID: userID, showsTitle: false)
        case .catches:
            MyCatchesSection(environment: environment, userID: userID, showsTitle: false)
        case .places:
            MyPlacesSection(environment: environment, userID: userID, showsTitle: false)
        case .photos:
            MyPhotosSection(environment: environment, userID: userID, showsTitle: false)
        }
    }
}
