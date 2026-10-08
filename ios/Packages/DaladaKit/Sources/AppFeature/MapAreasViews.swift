import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

/// Нацпарк, заповедник или погранзона: что важно при въезде, тарифы (если парк их публикует),
/// билеты и сайт, первоисточник и дата проверки. Работает без сети — по сохранённым слоям.
struct MapAreaView: View {
    let areaID: String

    @Environment(RulesStore.self) private var rules

    var body: some View {
        Group {
            if let pack = rules.areas, let area = pack.area(areaID) {
                content(area, pack: pack)
                    .transition(.skeletonReveal)
            } else {
                // Слои грузятся: вид зоны, текст о ней, тарифы.
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        SkeletonText(AppTypography.bodySmall, width: 140)
                        SkeletonText(AppTypography.body, lines: 4)
                        Skeleton(height: 120, cornerRadius: AppRadius.xl)
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
        // Слои загрузились — зона проявляется на месте скелетона (DesignKit).
        .animation(AppAnimation.smooth, value: rules.areas != nil)
        .navigationTitle(Text(verbatim: rules.areas?.area(areaID)?.name.text(for: RulesStore.language) ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .task { await rules.loadIfNeeded() }
    }

    private func content(_ area: MapArea, pack: MapAreasPack) -> some View {
        let language = RulesStore.language
        return ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Label(LocalizedStringKey(area.kind.titleKey), systemImage: area.kind.systemImage)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)

                Text(verbatim: area.info.text(for: language))
                    .font(AppTypography.body)

                if !area.fees.isEmpty {
                    fees(area.fees, pack: pack)
                }

                if area.ticketsURL != nil || area.websiteURL != nil {
                    VStack(spacing: AppSpacing.sm) {
                        if let tickets = area.ticketsURL {
                            Link(destination: tickets) {
                                Label("mapArea.tickets", systemImage: "ticket")
                                    .frame(maxWidth: .infinity)
                            }
                            .dsButton()
                        }
                        if let website = area.websiteURL {
                            Link(destination: website) {
                                Label("mapArea.website", systemImage: "safari")
                                    .frame(maxWidth: .infinity)
                            }
                            .dsButton(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("mapArea.source")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    if let url = area.sourceURL {
                        Link(destination: url) {
                            Text(verbatim: area.sourceTitle)
                                .multilineTextAlignment(.leading)
                        }
                        .font(AppTypography.bodySmall)
                    } else {
                        Text(verbatim: area.sourceTitle)
                            .font(AppTypography.bodySmall)
                    }
                    Text("mapArea.verified \(Self.date(area.verifiedOn))")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Text("mapArea.approximate")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
        }
    }

    private func fees(_ fees: MapArea.Fees, pack: MapAreasPack) -> some View {
        let year = RulesStore.almatyCalendar.component(.year, from: Date())
        let rows: [(LocalizedStringKey, Double?)] = [
            ("mapArea.fee.person", fees.person),
            ("mapArea.fee.car", fees.car),
            ("mapArea.fee.fishing", fees.fishing),
        ]
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(String(localized: "mapArea.fees"), systemImage: "banknote")
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if let mrp = row.1 {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0)
                            .font(AppTypography.bodySmall)
                        Spacer(minLength: AppSpacing.md)
                        Text(verbatim: Self.fee(mrp, tenge: pack.tenge(mrp: mrp, year: year)))
                            .font(AppTypography.bodyEmphasis)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            if let tenge = pack.mrpTenge(year: year) {
                Text("mapArea.fees.footer \(tenge.formatted(.number))")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .cardContentPadding()
        .cardStyle()
    }

    /// «0,7 МРП · 3 028 ₸».
    static func fee(_ mrp: Double, tenge: Int?) -> String {
        let value = String(localized: "mapArea.mrp \(mrp.formatted(.number.precision(.fractionLength(0...2))))")
        guard let tenge else { return value }
        return value + " · " + tenge.formatted(.number) + " ₸"
    }

    /// «2026-10-05» → дата на языке интерфейса.
    static func date(_ value: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return value }
        return date.formatted(.dateTime.day().month().year())
    }
}

extension MapAreaKind {
    var systemImage: String {
        switch self {
        case .nationalPark: "tree"
        case .natureReserve: "leaf"
        case .borderStrip, .borderZone: "flag"
        }
    }
}

/// Место в нацпарке или заповеднике: строка в карточке места со ссылкой на карточку парка (въезд,
/// тарифы, билеты). Не в парке — ничего.
struct PlaceParksSection: View {
    let coordinate: GeoPoint

    @Environment(RulesStore.self) private var rules

    var body: some View {
        Group {
            if let parks = rules.areas?.parks(containing: coordinate), !parks.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    ForEach(parks) { park in
                        NavigationLink {
                            MapAreaView(areaID: park.id)
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: park.kind.systemImage)
                                    .foregroundStyle(AppColors.success)
                                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                    Text(verbatim: park.name.text(for: RulesStore.language))
                                        .font(AppTypography.bodyEmphasis)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Text(park.kind == .natureReserve ? "mapArea.place.reserve" : "mapArea.place.park")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                Spacer(minLength: 0)
                                DisclosureChevron()
                            }
                            .cardContentPadding()
                            .cardStyle()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task { await rules.loadIfNeeded() }
    }
}
