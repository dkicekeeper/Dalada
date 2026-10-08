import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

// MARK: - Уровень в профиле

/// Уровень участника: очки, путь до следующего уровня; опытному — «Проверить правки» с числом.
struct ContributionCard: View {
    let environment: AppEnvironment
    let userID: UUID

    @State private var contribution: Contribution?
    @State private var showsDetails = false

    var body: some View {
        Group {
            if let contribution {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Button {
                        showsDetails = true
                    } label: {
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: contribution.level.systemImage)
                                .font(.system(size: AppIconSize.lg))
                                .foregroundStyle(AppColors.accent)
                                .frame(width: AppIconSize.xxl)
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                Text(LocalizedStringKey(contribution.level.titleKey))
                                    .font(AppTypography.bodyEmphasis)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(verbatim: subtitle(contribution))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            Spacer(minLength: 0)
                            DisclosureChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if contribution.nextLevel != nil {
                        LinearProgressBar(value: contribution.progress, animatesOnAppear: false)
                    }
                    if contribution.canReview {
                        NavigationLink {
                            SuggestionReviewView(environment: environment)
                        } label: {
                            Label {
                                Text("level.review \(contribution.reviewQueue)")
                            } icon: {
                                Image(systemName: "checkmark.seal")
                            }
                            .font(AppTypography.bodySmall)
                        }
                    }
                }
                .cardContentPadding()
                .cardStyle()
                .sheet(isPresented: $showsDetails) {
                    ContributionDetailsSheet(contribution: contribution)
                }
            }
        }
        .task(id: userID) { await load() }
    }

    /// «120 очков · до «Эксперта» — 80».
    private func subtitle(_ contribution: Contribution) -> String {
        var text = String(localized: "level.points \(contribution.points)")
        if let next = contribution.nextLevel, let threshold = contribution.nextLevelPoints {
            let left = max(threshold - contribution.points, 0)
            text += " · " + String(localized: "level.toNext \(String(localized: String.LocalizationValue(next.titleKey))) \(left)")
        }
        return text
    }

    private func load() async {
        guard let backend = environment.backend else { return }
        if let loaded = try? await backend.myContribution() {
            contribution = loaded
        }
    }
}

/// За что очки: по видам вклада и что открывают уровни.
struct ContributionDetailsSheet: View {
    let contribution: Contribution

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("level.kind.places", count: contribution.places, each: 20)
                    row("level.kind.photos", count: contribution.photos, each: 5)
                    row("level.kind.reports", count: contribution.reports, each: 5)
                    row("level.kind.reviews", count: contribution.reviews, each: 10)
                    row("level.kind.edits", count: contribution.edits, each: 10)
                    row("level.kind.helpful", count: contribution.helpful, each: 5)
                } header: {
                    Text("level.points \(contribution.points)")
                } footer: {
                    Text("level.kinds.footer")
                }
                Section {
                    ForEach(ContributorLevel.allCases, id: \.self) { level in
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: level.systemImage)
                                .foregroundStyle(level == contribution.level ? AppColors.accent : AppColors.textTertiary)
                                .frame(width: AppIconSize.md)
                            Text(LocalizedStringKey(level.titleKey))
                                .fontWeight(level == contribution.level ? .semibold : .regular)
                            Spacer(minLength: 0)
                            Text(verbatim: String(level.threshold))
                                .monospacedDigit()
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                } footer: {
                    Text("level.levels.footer")
                }
            }
            .navigationTitle("level.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
    }

    private func row(_ titleKey: LocalizedStringKey, count: Int, each: Int) -> some View {
        LabeledContent {
            Text(verbatim: "\(count) × \(each) = \(count * each)")
                .monospacedDigit()
        } label: {
            Text(titleKey)
        }
    }
}

// MARK: - Разбор правок

/// Правки мест от других участников: что предлагают и зачем; «Принять» меняет место, «Отклонить» —
/// нет. Автор правки узнает решение, но не узнает, кто разбирал.
struct SuggestionReviewView: View {
    let environment: AppEnvironment

    @State private var items: [SuggestionReviewItem] = []
    @State private var isLoaded = false
    @State private var working: UUID?
    @State private var errorText: String?
    @State private var openedPlace: PlaceSelection?

    var body: some View {
        List {
            if items.isEmpty && isLoaded {
                EmptyState(
                    icon: "checkmark.seal",
                    title: String(localized: "review.empty.title"),
                    description: String(localized: "review.empty")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(items) { item in
                Section {
                    changes(item)
                    if let note = item.note, !note.isEmpty {
                        Text(verbatim: "«" + note + "»")
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    HStack(spacing: AppSpacing.md) {
                        DSButton(String(localized: "review.accept"), size: .medium) {
                            Task { await decide(item, accept: true) }
                        }
                        DSButton(String(localized: "review.reject"), appearance: .secondary, role: .destructive, size: .medium) {
                            Task { await decide(item, accept: false) }
                        }
                        Spacer(minLength: 0)
                        Button("review.openPlace") {
                            openedPlace = PlaceSelection(id: item.placeID)
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(AppTypography.bodySmall)
                    .disabled(working != nil)
                } header: {
                    Text(verbatim: item.placeName)
                } footer: {
                    Text(verbatim: [item.authorUsername.map { "@" + $0 }, item.createdAt.formatted(date: .abbreviated, time: .omitted)]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                }
            }
        }
        .navigationTitle("review.title")
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $openedPlace) { selection in
            PlaceCardView(placeID: selection.id, environment: environment)
        }
        .alert(
            "review.failed",
            isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: errorText ?? "")
        }
    }

    @ViewBuilder
    private func changes(_ item: SuggestionReviewItem) -> some View {
        if let name = item.newName {
            LabeledContent("review.field.name") {
                Text(verbatim: item.placeName + " → " + name)
            }
        }
        if let type = item.newType {
            LabeledContent("review.field.type") {
                Text(LocalizedStringKey(type.titleKey))
            }
        }
        if let description = item.newDescription {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("review.field.description")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                Text(verbatim: description.isEmpty ? String(localized: "review.field.descriptionRemoved") : description)
                    .font(AppTypography.bodySmall)
            }
        }
        if item.changesAttributes {
            Label("review.field.attributes", systemImage: "info.circle")
                .font(AppTypography.bodySmall)
        }
    }

    private func load() async {
        defer { isLoaded = true }
        guard let backend = environment.backend else { return }
        do {
            items = try await backend.suggestionReviewQueue()
        } catch {
            errorText = CommunityMessage.text(for: error)
        }
    }

    private func decide(_ item: SuggestionReviewItem, accept: Bool) async {
        guard let backend = environment.backend else { return }
        working = item.id
        defer { working = nil }
        do {
            try await backend.reviewSuggestion(item.id, accept: accept)
            items.removeAll { $0.id == item.id }
        } catch {
            errorText = CommunityMessage.text(for: error)
        }
    }
}
