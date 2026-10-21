import Backend
import DaladaCore
import DaladaUI
import DesignComponents
import DesignTokens
import MapEngine
import Persistence
import SwiftUI

/// Строка места: иконка типа, название, видимость, статус модерации (`ItemRow` из DesignKit).
struct PlaceRow: View {
    let place: PlaceSummary
    /// Строка стеклянной секции отступает сама (DesignKit 8.1.0); в стопке со своими промежутками — 0.
    var verticalPadding: CGFloat = AppSpacing.md

    var body: some View {
        ItemRow(place.name, meta: [MetaLine(labels, separator: .space)], leading: .symbol(place.type.systemImage),
                verticalPadding: verticalPadding) {
            DisclosureChevron()
        }
    }

    private var labels: [MetaItem] {
        var labels: [MetaItem] = [
            .label(Text(LocalizedStringKey(place.visibility.titleKey)), systemImage: place.visibility.systemImage),
        ]
        if place.status == .pending {
            labels.append(.label(Text("place.status.pending"), systemImage: "hourglass", tint: AppColors.warning))
        }
        return labels
    }
}

/// Строка «Лайфхаков»: значок слева, справа заголовок и под ним подзаголовок (UniversalRow из
/// DesignKit; шеврон добавляет NavigationLink).
private struct LifehackRow: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    var subtitle: String?

    /// Переход на экран — с шевроном; действие («Собраться») — без.
    var showsChevron = true

    /// Где начинается текст: после значка 24 pt и промежутка (метка ссылки не передаёт отступ).
    static let dividerInset = AppIconSize.lg + AppSpacing.md

    var body: some View {
        UniversalRow(leadingIcon: .sfSymbol(systemImage, color: AppColors.accent, size: AppIconSize.lg)) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(titleKey)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        } trailing: {
            if showsChevron {
                DisclosureChevron()
            }
        }
        .contentShape(Rectangle())
    }
}

/// Вкладка «Лайфхаки»: «Перед поездкой» — сборы, чеклисты, экипировка, карты без сети, правила и
/// запреты; «Знания и статьи» — справочник рыб и статьи.
struct LifehacksHomeView: View {
    let environment: AppEnvironment

    @Environment(RulesStore.self) private var rules
    @Environment(ListsStore.self) private var lists
    @Environment(ArticlesStore.self) private var articles
    @State private var startsPacking = false
    @State private var opened: UUID?
    @State private var offlineMaps = OfflineMaps.shared

    var body: some View {
        NavigationStack {
            // DesignKit 8.0.0: стеклянные секции на странице (до этого List).
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    FormSection(
                        header: String(localized: "lifehacks.section.prep"),
                        footer: lists.hasUnsyncedChanges ? String(localized: "lists.unsynced") : nil
                    ) {
                        // Ближайшие сборы с прогрессом.
                        if let packing = lists.upcomingPacking {
                            NavigationLink {
                                ChecklistDetailView(checklistID: packing.id)
                            } label: {
                                ChecklistSummaryRow(checklist: packing)
                                    .padding(.vertical, AppSpacing.md)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            startsPacking = true
                        } label: {
                            LifehackRow(titleKey: "packing.start", systemImage: "bag.badge.plus", showsChevron: false)
                        }
                        .buttonStyle(.plain)
                        .rowDividerInset(LifehackRow.dividerInset)
                        NavigationLink {
                            ChecklistsView()
                        } label: {
                            LifehackRow(
                                titleKey: "checklists.title",
                                systemImage: "checklist",
                                subtitle: String(localized: "checklists.summary \(lists.packingLists.count) \(lists.ownLists.count)")
                            )
                        }
                        .buttonStyle(.plain)
                        .rowDividerInset(LifehackRow.dividerInset)
                        // Общие сборы с друзьями: кто что берёт.
                        NavigationLink {
                            SharedPackingsView(environment: environment)
                        } label: {
                            LifehackRow(
                                titleKey: "sharedPacking.title",
                                systemImage: "person.2.badge.gearshape",
                                subtitle: String(localized: "sharedPacking.subtitle")
                            )
                        }
                        .buttonStyle(.plain)
                        .rowDividerInset(LifehackRow.dividerInset)
                        NavigationLink {
                            GearListView()
                        } label: {
                            LifehackRow(
                                titleKey: "gear.title",
                                systemImage: "backpack",
                                subtitle: lists.gear.isEmpty ? String(localized: "gear.summary.none") : GearFormat.summary(lists.gear)
                            )
                        }
                        .buttonStyle(.plain)
                        .rowDividerInset(LifehackRow.dividerInset)
                        NavigationLink {
                            OfflineMapsView(environment: environment)
                        } label: {
                            LifehackRow(
                                titleKey: "offlineMaps.title",
                                systemImage: "map",
                                subtitle: OfflineMapsFormat.summary(offlineMaps)
                            )
                        }
                        .buttonStyle(.plain)
                        .rowDividerInset(LifehackRow.dividerInset)
                        // Запреты проверяют перед выездом — рядом со сборами, а не среди статей.
                        NavigationLink {
                            RulesListView(environment: environment)
                        } label: {
                            LifehackRow(titleKey: "rules.title", systemImage: "exclamationmark.shield", subtitle: rulesSummary)
                        }
                        .buttonStyle(.plain)
                        .rowDividerInset(LifehackRow.dividerInset)
                    }

                    FormSection(header: String(localized: "lifehacks.section.knowledge")) {
                        NavigationLink {
                            FishGuideView()
                        } label: {
                            LifehackRow(titleKey: "fish.guide.title", systemImage: "fish")
                        }
                        .buttonStyle(.plain)
                        .rowDividerInset(LifehackRow.dividerInset)
                        // Три последние статьи и ссылка на все.
                        ForEach(articles.articles.prefix(3)) { article in
                            NavigationLink {
                                ArticleView(article: article)
                            } label: {
                                ArticleRow(article: article)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .rowDividerInset(ArticleRow.dividerInset)
                        }
                        if articles.articles.isEmpty {
                            Text("articles.empty")
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, AppSpacing.lg)
                        } else {
                            NavigationLink {
                                ArticlesListView()
                            } label: {
                                LifehackRow(titleKey: "articles.all", systemImage: "books.vertical")
                            }
                            .buttonStyle(.plain)
                            .rowDividerInset(LifehackRow.dividerInset)
                        }
                    }
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
            }
            .navigationTitle("tab.lifehacks")
            .navigationDestination(item: $opened) { id in
                ChecklistDetailView(checklistID: id)
            }
            .sheet(isPresented: $startsPacking) {
                StartPackingView { opened = $0.id }
                    .environment(lists)
            }
            .task { await rules.loadIfNeeded() }
            .task { await lists.loadTemplates() }
            .task { await articles.loadIfNeeded() }
        }
    }

    /// «Сейчас действуют запреты: 2» или ближайший: «Капшагайское водохранилище — с 5 апреля».
    private var rulesSummary: String? {
        guard let pack = rules.pack else { return nil }
        let today = RulesStore.today
        let active = pack.zones.filter { pack.banState(ofZone: $0.id, on: today) == .active }
        if !active.isEmpty {
            return String(localized: "rules.summary.active \(active.count)")
        }
        let upcoming = pack.regulations
            .filter { $0.kind == .fishingBan }
            .compactMap { regulation -> (Regulation, CalendarDay)? in
                switch pack.status(of: regulation, on: today) {
                case .soon(let start, _, _), .later(let start, _): (regulation, start)
                case .active, .yearRound: nil
                }
            }
            .min { $0.1 < $1.1 }
        guard let next = upcoming,
              let zoneID = next.0.zoneIDs.first,
              let zone = pack.zone(zoneID)
        else { return nil }
        return String(localized: "rules.summary.next \(zone.name.text(for: RulesStore.language)) \(RuleFormat.day(next.1))")
    }
}
