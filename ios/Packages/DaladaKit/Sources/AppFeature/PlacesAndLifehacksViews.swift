import Backend
import DaladaCore
import DaladaUI
import DesignComponents
import DesignTokens
import MapEngine
import Persistence
import SwiftUI

/// Строка места: иконка типа, название, видимость, статус модерации.
struct PlaceRow: View {
    let place: PlaceSummary

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: place.type.systemImage)
                .font(.system(size: AppIconSize.md))
                .foregroundStyle(AppColors.accent)
                .frame(width: AppIconSize.avatar, height: AppIconSize.avatar)
                .background(AppColors.pale(AppColors.accent), in: Circle())
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: place.name)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                HStack(spacing: AppSpacing.sm) {
                    Label(LocalizedStringKey(place.visibility.titleKey), systemImage: place.visibility.systemImage)
                    if place.status == .pending {
                        Label("place.status.pending", systemImage: "hourglass")
                            .foregroundStyle(AppColors.warning)
                    }
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: 0)
            DisclosureChevron()
        }
        .contentShape(Rectangle())
    }
}

/// Строка «Лайфхаков»: значок слева, справа заголовок и под ним подзаголовок (UniversalRow из
/// DesignKit; шеврон добавляет NavigationLink).
private struct LifehackRow: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    var subtitle: String?

    var body: some View {
        UniversalRow(config: .settings, leadingIcon: .sfSymbol(systemImage, color: AppColors.accent)) {
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
            EmptyView()
        }
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
            List {
                Section {
                    // Ближайшие сборы с прогрессом.
                    if let packing = lists.upcomingPacking {
                        NavigationLink {
                            ChecklistDetailView(checklistID: packing.id)
                        } label: {
                            ChecklistSummaryRow(checklist: packing)
                        }
                    }
                    Button {
                        startsPacking = true
                    } label: {
                        LifehackRow(titleKey: "packing.start", systemImage: "bag.badge.plus")
                    }
                    NavigationLink {
                        ChecklistsView()
                    } label: {
                        LifehackRow(
                            titleKey: "checklists.title",
                            systemImage: "checklist",
                            subtitle: String(localized: "checklists.summary \(lists.packingLists.count) \(lists.ownLists.count)")
                        )
                    }
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
                    NavigationLink {
                        GearListView()
                    } label: {
                        LifehackRow(
                            titleKey: "gear.title",
                            systemImage: "backpack",
                            subtitle: lists.gear.isEmpty ? String(localized: "gear.summary.none") : GearFormat.summary(lists.gear)
                        )
                    }
                    NavigationLink {
                        OfflineMapsView(environment: environment)
                    } label: {
                        LifehackRow(
                            titleKey: "offlineMaps.title",
                            systemImage: "map",
                            subtitle: OfflineMapsFormat.summary(offlineMaps)
                        )
                    }
                    // Запреты проверяют перед выездом — рядом со сборами, а не среди статей.
                    NavigationLink {
                        RulesListView(environment: environment)
                    } label: {
                        LifehackRow(titleKey: "rules.title", systemImage: "exclamationmark.shield", subtitle: rulesSummary)
                    }
                } header: {
                    Text("lifehacks.section.prep")
                } footer: {
                    if lists.hasUnsyncedChanges {
                        Label("lists.unsynced", systemImage: "icloud.slash")
                    }
                }

                Section {
                    NavigationLink {
                        FishGuideView()
                    } label: {
                        LifehackRow(titleKey: "fish.guide.title", systemImage: "fish")
                    }
                    // Три последние статьи и ссылка на все.
                    ForEach(articles.articles.prefix(3)) { article in
                        NavigationLink {
                            ArticleView(article: article)
                        } label: {
                            ArticleRow(article: article)
                        }
                    }
                    if articles.articles.isEmpty {
                        Text("articles.empty")
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    } else {
                        NavigationLink {
                            ArticlesListView()
                        } label: {
                            LifehackRow(titleKey: "articles.all", systemImage: "books.vertical")
                        }
                    }
                } header: {
                    Text("lifehacks.section.knowledge")
                }
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
