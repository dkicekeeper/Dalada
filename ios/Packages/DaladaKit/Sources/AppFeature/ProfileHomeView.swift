import Backend
import DaladaCore
import DaladaUI
import DesignComponents
import DesignTokens
import Persistence
import SwiftUI
import Sync

/// Вкладка «Профиль»: шапка и шестерёнка в панели — настройки профиля, статистика, очередь отправки, мои друзья,
/// поездки, уловы, места и фото по чипам, достижения. Гостю — вход. Карточка сервера — только когда
/// с ним проблема.
struct ProfileHomeView: View {
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @State private var connection: ConnectionState = .checking
    @State private var showsAbout = false
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    content
                    if connection.isProblem {
                        BackendStatusCard(state: connection)
                    }
                }
                .screenPadding()
                .padding(.bottom, AppSpacing.xl)
            }
            .navigationTitle("tab.profile")
            .navigationDestination(isPresented: $showsAbout) {
                AboutView()
            }
            .navigationDestination(isPresented: $showsSettings) {
                ProfileSettingsView(environment: environment)
            }
            .task { await checkConnection() }
            .toolbar {
                if session.profile == nil {
                    // Гостю — поддержка и документы.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsAbout = true
                        } label: {
                            Image(systemName: "info.circle")
                                .accessibilityLabel(Text("about.title"))
                        }
                    }
                } else {
                    // Настройки — на привычном месте, а не только по нажатию на шапку.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .accessibilityLabel(Text("profile.settings.title"))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .loading:
            // Профиль грузится: карточка профиля.
            PersonRowSkeleton(style: .card)
        case .guest:
            SignInCard()
            historyPlaceholder
        case .needsUsername, .signedIn:
            if let profile = session.profile {
                NavigationLink {
                    ProfileSettingsView(environment: environment)
                } label: {
                    ProfileHeader(profile: profile)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("profile.settings.title"))
                ProfileStatsCard(environment: environment, userID: profile.id)
                StreakCard(environment: environment, userID: profile.id)
                ContributionCard(environment: environment, userID: profile.id)
                PendingQueueSection()
                MyFriendsSection(environment: environment, userID: profile.id)
                // Поездки, уловы, места и фото — по чипам, а не четырьмя разделами подряд.
                ProfileContentTabs(environment: environment, userID: profile.id)
                AchievementsSection(environment: environment, userID: profile.id)
            } else {
                historyPlaceholder
            }
        case .profileUnavailable(let message):
            EmptyState(
                icon: "wifi.slash",
                title: String(localized: "profile.unavailable"),
                description: message,
                actionTitle: String(localized: "common.retry"),
                action: { Task { await session.reloadProfile() } },
                style: .error
            )
        }
    }

    private func checkConnection() async {
        guard let backend = environment.backend else {
            connection = .notConfigured
            return
        }
        connection = await backend.checkConnection()
    }

    private var historyPlaceholder: some View {
        PlaceholderScreen(
            icon: "figure.fishing",
            title: String(localized: "profile.empty.title"),
            description: String(localized: "profile.empty.description")
        )
    }
}

// MARK: - Разделы профиля

/// Раздел профиля: заголовок со значком, «Все» (если есть куда) и карточка с содержимым.
/// Во вкладке профиля заголовок не нужен — его роль играет чип (`showsTitle: false`).
struct ProfileSection<Content: View, Destination: View>: View {
    let titleKey: String.LocalizationValue
    let systemImage: String
    let showsAll: Bool
    let showsTitle: Bool
    let destination: Destination
    let content: Content

    init(
        _ titleKey: String.LocalizationValue,
        systemImage: String,
        showsAll: Bool = true,
        showsTitle: Bool = true,
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder content: () -> Content
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.showsAll = showsAll
        self.showsTitle = showsTitle
        self.destination = destination()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if showsTitle {
                SectionHeader(String(localized: titleKey), systemImage: systemImage) {
                    if showsAll { allLink }
                }
            } else if showsAll {
                // Во вкладке профиля заголовка нет: ссылка «Все» одна у правого края.
                HStack {
                    Spacer(minLength: 0)
                    allLink.font(AppTypography.bodySmall)
                }
            }
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardContentPadding()
            .cardStyle()
        }
    }

    private var allLink: some View {
        NavigationLink {
            destination
        } label: {
            Text("trips.all")
        }
    }
}

/// Подсказка в пустом разделе профиля.
struct ProfileSectionHint: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(AppTypography.bodySmall)
            .foregroundStyle(AppColors.textSecondary)
    }
}

/// «Мои друзья»: запросы в друзья, лента аватаров (нажатие — профиль друга), «Все» — друзья и
/// поиск. Без друзей — подсказка и «Найти людей».
struct MyFriendsSection: View {
    let environment: AppEnvironment
    let userID: UUID

    @State private var friends: [Friend] = []
    @State private var incomingCount = 0
    @State private var isLoaded = false

    var body: some View {
        ProfileSection("profile.friends.title", systemImage: "person.2") {
            FriendsView(environment: environment)
        } content: {
            if incomingCount > 0 {
                NavigationLink {
                    FriendsView(environment: environment)
                } label: {
                    UniversalRow(config: .info, leadingIcon: .sfSymbol("person.badge.plus", color: AppColors.accent)) {
                        Text("friends.requests")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColors.textPrimary)
                    } trailing: {
                        Badge("\(incomingCount)", color: AppColors.destructive, style: .filled)
                        DisclosureChevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !friends.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: AppSpacing.lg) {
                        ForEach(friends) { friend in
                            friendAvatar(friend)
                        }
                    }
                }
            } else if isLoaded {
                ProfileSectionHint(text: String(localized: "friends.empty"))
                NavigationLink {
                    FindPeopleView(environment: environment)
                } label: {
                    Label("friends.find", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .dsButton(.secondary)
            } else {
                // Аватары друзей той же формы, пока грузятся.
                HStack(alignment: .top, spacing: AppSpacing.lg) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(spacing: AppSpacing.xs) {
                            Skeleton.circle(AppIconSize.Tile.md)
                            SkeletonText(AppTypography.caption, width: AppIconSize.Tile.md)
                        }
                        .frame(width: AppIconSize.Tile.xxxl)
                    }
                }
                .shimmer()
                .skeletonLoadingLabel()
            }
        }
        .task(id: userID) { await load() }
    }

    @ViewBuilder
    private func friendAvatar(_ friend: Friend) -> some View {
        let label = VStack(spacing: AppSpacing.xs) {
            PersonAvatar(name: friend.displayName ?? friend.username, path: friend.avatarPath, size: AppIconSize.Tile.md)
            Text(verbatim: shortName(friend))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
        }
        .frame(width: AppIconSize.Tile.xxxl)
        if let username = friend.username {
            NavigationLink {
                UserProfileView(username: username, environment: environment)
            } label: {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    /// Имя под аватаром: первое слово имени или @username.
    private func shortName(_ friend: Friend) -> String {
        if let name = friend.displayName?.split(separator: " ").first {
            return String(name)
        }
        return friend.username.map { "@" + $0 } ?? String(localized: "profile.noName")
    }

    private func load() async {
        defer { isLoaded = true }
        guard let backend = environment.backend else { return }
        if let loaded = try? await backend.myFriends() {
            friends = loaded
            // Сохраняем — чтобы отметить друзей на финише поездки без сети.
            try? await environment.cache.save(loaded, for: CacheKey.friends(userID))
        }
        if let requests = try? await backend.myFriendRequests() {
            incomingCount = requests.filter { $0.direction == .incoming }.count
        }
    }
}

/// «Мои уловы» (RPC `my_catches`): три последних в профиле, «Все» — полный список. Обновляется
/// после отправки очереди; без сети — сохранённый список.
struct MyCatchesSection: View {
    let environment: AppEnvironment
    let userID: UUID
    var showsTitle = true

    @Environment(SyncEngine.self) private var sync
    @State private var catches: [MyCatch] = []
    @State private var isLoaded = false

    var body: some View {
        ProfileSection("profile.catches.title", systemImage: "fish", showsAll: !catches.isEmpty, showsTitle: showsTitle) {
            MyCatchesView(environment: environment, userID: userID)
        } content: {
            if !catches.isEmpty {
                ForEach(catches.prefix(3)) { item in
                    MyCatchRow(item: item)
                        .ownCatchActions(catchID: item.id, environment: environment) {
                            Task { catches = await MyCatchesLoader(environment: environment, userID: userID).load() }
                        }
                }
            } else if isLoaded {
                ProfileSectionHint(text: String(localized: "profile.catches.empty"))
            } else {
                ForEach(0..<2, id: \.self) { _ in SkeletonRow(showsIcon: false) }
            }
        }
        .task(id: userID) {
            catches = await MyCatchesLoader(environment: environment, userID: userID).load()
            isLoaded = true
        }
        .onChange(of: sync.sentCount) { _, _ in
            Task { catches = await MyCatchesLoader(environment: environment, userID: userID).load() }
        }
    }
}

/// Все свои уловы, сверху — личные рекорды по видам.
struct MyCatchesView: View {
    let environment: AppEnvironment
    let userID: UUID

    @State private var catches: [MyCatch] = []
    @State private var records: [PersonalRecord] = []
    @State private var isLoaded = false

    var body: some View {
        Group {
            if catches.isEmpty && isLoaded {
                PlaceholderScreen(
                    icon: "fish",
                    title: String(localized: "profile.catches.title"),
                    description: String(localized: "profile.catches.empty")
                )
            } else {
                List {
                    if !records.isEmpty {
                        PersonalRecordsSection(records: records)
                    }
                    Section {
                        ForEach(catches) { item in
                            MyCatchRow(item: item)
                                .ownCatchActions(catchID: item.id, environment: environment, inList: true) {
                                    Task { await load() }
                                }
                        }
                    } header: {
                        if !records.isEmpty {
                            Text("records.allCatches")
                        }
                    }
                }
            }
        }
        .navigationTitle("profile.catches.title")
        .task { await load() }
    }

    private func load() async {
        async let loadedCatches = MyCatchesLoader(environment: environment, userID: userID).load(limit: 200)
        async let loadedRecords = RecordsLoader(environment: environment, userID: userID).load()
        (catches, records) = await (loadedCatches, loadedRecords)
        isLoaded = true
    }
}

/// Улов: вид, вес, длина, «отпущена», место и дата.
private struct MyCatchRow: View {
    let item: MyCatch

    @Environment(SpeciesStore.self) private var speciesStore

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                CatchSummaryRow(
                    speciesName: speciesStore.name(for: item.speciesID),
                    count: item.count,
                    weightGrams: item.weightGrams,
                    lengthMillimeters: item.lengthMillimeters,
                    released: item.released
                )
                HStack(spacing: AppSpacing.xs) {
                    if let placeName = item.placeName {
                        Text(verbatim: placeName)
                        Text(verbatim: "·")
                    }
                    Text(item.at, format: .dateTime.day().month().year())
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            }
            // Картинка улова для Stories и Telegram.
            CatchShareCardButton(catchID: item.id, isPublic: item.visibility == .public)
        }
        .task { await speciesStore.loadIfNeeded() }
    }
}

/// Свои уловы: сеть, без неё — сохранённый список.
struct MyCatchesLoader {
    let environment: AppEnvironment
    let userID: UUID

    func load(limit: Int = 20) async -> [MyCatch] {
        let key = CacheKey.myCatches(userID)
        if let backend = environment.backend, let loaded = try? await backend.myCatches(limit: limit) {
            if limit <= 20 {
                try? await environment.cache.save(loaded, for: key)
            }
            return loaded
        }
        let saved = (try? await environment.cache.load([MyCatch].self, for: key)) ?? []
        return Array(saved.prefix(limit))
    }
}

/// «Мои места»: три последних в профиле, «Все» — полный список (свои места любой видимости,
/// включая места на проверке). Нажатие открывает карточку места.
struct MyPlacesSection: View {
    let environment: AppEnvironment
    let userID: UUID
    var showsTitle = true

    @Environment(SyncEngine.self) private var sync
    @State private var places: [PlaceSummary] = []
    @State private var isLoaded = false
    @State private var selected: PlaceSelection?

    var body: some View {
        ProfileSection("places.mine.title", systemImage: "mappin.and.ellipse", showsAll: places.count > 3, showsTitle: showsTitle) {
            MyPlacesView(environment: environment)
        } content: {
            if !places.isEmpty {
                ForEach(places.prefix(3)) { place in
                    Button {
                        selected = PlaceSelection(id: place.id)
                    } label: {
                        PlaceRow(place: place)
                    }
                    .buttonStyle(.plain)
                }
            } else if isLoaded {
                ProfileSectionHint(text: String(localized: "places.mine.empty.description"))
            } else {
                ForEach(0..<2, id: \.self) { _ in SkeletonRow() }
            }
        }
        .task(id: userID) { await load() }
        .onChange(of: sync.sentCount) { _, _ in
            Task { await load() }
        }
        .sheet(item: $selected, onDismiss: { Task { await load() } }) { selection in
            PlaceCardView(placeID: selection.id, environment: environment)
        }
    }

    private func load() async {
        defer { isLoaded = true }
        let key = CacheKey.myPlaces(userID)
        if let backend = environment.backend, let loaded = try? await backend.myPlaces() {
            places = loaded
            try? await environment.cache.save(loaded, for: key)
        } else if places.isEmpty, let saved = try? await environment.cache.load([PlaceSummary].self, for: key) {
            places = saved
        }
    }
}

/// Счётчики профиля: дни на природе, поездки, километры, уловы (RPC `my_stats`).
/// Без сети — сохранённые; обновляются после отправки очереди.
struct ProfileStatsCard: View {
    let environment: AppEnvironment
    let userID: UUID

    @Environment(SyncEngine.self) private var sync
    @State private var stats: UserStats?
    @State private var isLoaded = false

    var body: some View {
        Group {
            if let stats {
                StatsStrip(items: [
                    .init(value: String(stats.daysOutdoors), title: String(localized: "stats.days")),
                    .init(value: String(stats.tripsCount), title: String(localized: "stats.trips")),
                    .init(
                        value: (Double(stats.distanceM) / 1000).formatted(.number.precision(.fractionLength(0))),
                        title: String(localized: "stats.km")
                    ),
                    .init(value: String(stats.catchesCount), title: String(localized: "stats.catches")),
                ])
            } else if !isLoaded {
                StatsStripSkeleton(count: 4)
            }
        }
        .task(id: userID) { await load() }
        .onChange(of: sync.sentCount) { _, _ in
            Task { await load() }
        }
    }

    private func load() async {
        defer { isLoaded = true }
        let key = CacheKey.stats(userID)
        if let backend = environment.backend, let loaded = try? await backend.myStats() {
            stats = loaded
            try? await environment.cache.save(loaded, for: key)
        } else if stats == nil {
            stats = try? await environment.cache.load(UserStats.self, for: key)
        }
    }
}

/// Серия: недели подряд с выездом, лучшая серия и что делать на этой неделе. Пока не было ни одной
/// засчитанной недели — карточки нет. Без сети — сохранённая.
struct StreakCard: View {
    let environment: AppEnvironment
    let userID: UUID

    @Environment(SyncEngine.self) private var sync
    @State private var streak: Streak?
    @State private var isLoaded = false

    var body: some View {
        Group {
            if let streak {
                if streak.bestWeeks > 0 {
                    DesignComponents.StreakCard(
                        systemImage: streak.freeze != nil && !streak.thisWeekDone ? "snowflake" : "flame.fill",
                        isActive: streak.currentWeeks > 0,
                        title: String(localized: "streak.current \(streak.currentWeeks)"),
                        subtitle: String(localized: String.LocalizationValue(streak.hintKey)),
                        value: String(streak.bestWeeks),
                        valueCaption: String(localized: "streak.best")
                    )
                }
            } else if !isLoaded {
                StreakCardSkeleton()
            }
        }
        .task(id: userID) { await load() }
        .onChange(of: sync.sentCount) { _, _ in
            Task { await load() }
        }
    }

    private func load() async {
        defer { isLoaded = true }
        let key = CacheKey.streak(userID)
        if let backend = environment.backend, let loaded = try? await backend.myStreak() {
            streak = loaded
            try? await environment.cache.save(loaded, for: key)
        } else if streak == nil {
            streak = try? await environment.cache.load(Streak.self, for: key)
        }
    }
}

/// Шапка профиля: аватар, имя, @username, город; нажатие открывает настройки профиля.
struct ProfileHeader: View {
    let profile: UserProfile

    var body: some View {
        // Свой PersonRow (FriendsViews) принимает модель Dalada; здесь строка из DesignKit.
        DesignComponents.PersonRow(
            name: profile.displayName ?? String(localized: "profile.noName"),
            subtitle: profile.username.map { "@" + $0 },
            detail: profile.city,
            avatar: PersonAvatar(name: profile.displayName ?? profile.username, path: profile.avatarPath, size: AppIconSize.Tile.xl),
            style: .card
        ) {
            DisclosureChevron()
        }
        .contentShape(Rectangle())
    }
}

extension ConnectionState {
    /// Сервер не настроен или недоступен — стоит показать пользователю.
    var isProblem: Bool {
        switch self {
        case .notConfigured, .failed: true
        case .checking, .connected: false
        }
    }
}

/// Карточка «Сервер: подключено / нет соединения / не настроен».
struct BackendStatusCard: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("backend.status.title")
                    .font(AppTypography.bodyEmphasis)
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .cardContentPadding()
        .cardStyle()
    }

    private var message: String {
        switch state {
        case .notConfigured: String(localized: "backend.status.notConfigured")
        case .checking: String(localized: "backend.status.checking")
        case .connected: String(localized: "backend.status.connected")
        case .failed(let reason): String(localized: "backend.status.failed") + " — " + reason
        }
    }

    private var symbol: String {
        switch state {
        case .connected: "checkmark.circle.fill"
        case .checking: "arrow.triangle.2.circlepath"
        case .notConfigured, .failed: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .connected: AppColors.success
        case .checking: AppColors.textSecondary
        case .notConfigured, .failed: AppColors.warning
        }
    }
}

#Preview {
    ProfileHomeView(environment: .preview)
        .environment(SessionStore(backend: nil))
        .environment(SpeciesStore(backend: nil))
        .environment(SyncEngine(outbox: AppEnvironment.preview.database.outbox, sender: UnavailableSender()))
}
