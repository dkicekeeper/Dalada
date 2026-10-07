import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

/// «Смотритель места»: у кого больше всего подтверждённых отчётов здесь за 60 дней. Нажатие — профиль
/// (после входа).
struct PlaceStewardRow: View {
    let steward: PlaceSteward
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session

    var body: some View {
        if session.profile != nil, let username = steward.username {
            NavigationLink {
                UserProfileView(username: username, environment: environment)
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: AppSpacing.sm) {
            PersonAvatar(name: steward.name, path: steward.avatarPath, size: AppIconSize.xxl)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Label("steward.title", systemImage: "star.circle.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.accent)
                Text(verbatim: steward.name ?? String(localized: "profile.noName"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                Text("steward.count \(steward.checkins) \(PlaceSteward.windowDays)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .cardContentPadding()
        .cardStyle()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// «Рекорды места»: самый тяжёлый улов каждого вида с фото из подтверждённого отчёта.
struct PlaceRecordsView: View {
    let records: [PlaceRecord]
    let photoURLs: [String: URL]

    @Environment(SpeciesStore.self) private var speciesStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label("records.place.title", systemImage: "trophy")
                .font(AppTypography.bodyEmphasis)
            ForEach(records.prefix(5)) { record in
                HStack(spacing: AppSpacing.sm) {
                    RemotePhoto(path: record.photoThumbPath, url: photoURLs[record.photoThumbPath])
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(verbatim: speciesStore.name(for: record.speciesID) + " · " + CatchFormat.weight(grams: record.weightGrams))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(verbatim: [record.authorName, record.caughtAt.formatted(date: .abbreviated, time: .omitted)]
                            .compactMap { $0 }
                            .joined(separator: " · "))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            Text("records.place.hint")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .cardContentPadding()
        .cardStyle()
    }
}
