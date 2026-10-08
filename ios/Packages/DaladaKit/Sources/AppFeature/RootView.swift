import DaladaCore
import DaladaUI
import DesignComponents
import SwiftUI
import Sync

/// Корень приложения: Главная, Карта, Места, Лайфхаки, Профиль (docs/04-beta/M10-home.md).
public struct RootView: View {
    private let environment: AppEnvironment
    private let background: BackgroundSync

    @Environment(\.scenePhase) private var scenePhase
    @State private var session: SessionStore
    @State private var species: SpeciesStore
    @State private var sync: SyncEngine
    @State private var recorder: TripRecorder
    @State private var liveShare: LiveShareController
    @State private var reactions: ReactionStore
    @State private var rules: RulesStore
    @State private var lists: ListsStore
    @State private var articles: ArticlesStore
    @State private var places: PlacesStore
    @State private var avatars: AvatarStore
    @State private var router = AppRouter()
    /// Знакомство при первом запуске пройдено (или пропущено).
    @AppStorage("intro.completed") private var introCompleted = false
    /// Вид поездки, выбранный в листе «Начать поездку»: запись начинается, когда лист закроется.
    @State private var pendingTripActivity: TripActivity?
    /// Открытая ссылка-приглашение `dalada://u/<username>`.
    @State private var profileLink: ProfileLink?
    /// Обсуждение из пуша `dalada://thread/<id>`.
    @State private var threadLink: ThreadLinkItem?
    /// Поездка из пуша `dalada://trip/<id>` (комментарий, поездка друга).
    @State private var tripLink: TripLinkItem?
    /// Комментарии из пуша `dalada://comments/<вид>/<id>`.
    @State private var commentsLink: CommentsLinkItem?
    @State private var packingLink: PackingLinkItem?
    /// Приглашение в поездку по ссылке `dalada://trip-invite/<токен>`: ждёт входа, если гость.
    @AppStorage("tripInvite.pending") private var pendingTripInvite = ""
    @State private var inviteError: String?
    @State private var inviteNeedsSignIn = false
    /// Место по ссылке `dalada://place/<id>` («Поделиться»).
    @State private var placeLink: PlaceSelection?

    public init(environment: AppEnvironment, background: BackgroundSync) {
        self.environment = environment
        self.background = background
        _session = State(initialValue: SessionStore(
            backend: environment.backend, cache: environment.cache, database: environment.database
        ))
        _species = State(initialValue: SpeciesStore(backend: environment.backend, cache: environment.cache))
        _sync = State(initialValue: background.engine)
        // Трансляция геопозиции друзьям получает точки записи и выключается на финише.
        let recorder = TripRecorder(store: environment.database.trips)
        let live = LiveShareController(backend: environment.backend)
        recorder.onLocation = { [weak live] point, accuracy, date in
            live?.didRecord(point, accuracy: accuracy, at: date)
        }
        recorder.onEnd = { [weak live] in
            guard let live else { return }
            Task { await live.stop() }
        }
        _recorder = State(initialValue: recorder)
        _liveShare = State(initialValue: live)
        _reactions = State(initialValue: ReactionStore(backend: environment.backend))
        _rules = State(initialValue: RulesStore(backend: environment.backend, cache: environment.cache))
        _lists = State(initialValue: ListsStore(
            backend: environment.backend, database: environment.database, cache: environment.cache
        ))
        _articles = State(initialValue: ArticlesStore(backend: environment.backend, cache: environment.cache))
        _places = State(initialValue: PlacesStore(backend: environment.backend, cache: environment.cache))
        _avatars = State(initialValue: AvatarStore(backend: environment.backend))
    }

    public var body: some View {
        TabView(selection: $router.selection) {
            Tab("tab.home", systemImage: "house", value: AppTab.home) {
                HomeView(environment: environment)
            }
            Tab("tab.map", systemImage: "map", value: AppTab.map) {
                MapHomeView(environment: environment)
            }
            Tab("tab.places", systemImage: "mappin.and.ellipse", value: AppTab.places) {
                PlacesHomeView(environment: environment)
            }
            Tab("tab.lifehacks", systemImage: "lightbulb", value: AppTab.lifehacks) {
                LifehacksHomeView(environment: environment)
            }
            Tab("tab.profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                ProfileHomeView(environment: environment)
            }
        }
        // Идущая запись поездки — мини-плеер над вкладками.
        .modifier(TripAccessoryModifier(isEnabled: recorder.isActive) { router.showsRecording = true })
        // Знакомство — поверх вкладок, один раз; вход отсюда открывает согласие и username.
        .overlay {
            if !introCompleted {
                IntroOnboardingView(environment: environment) {
                    withAnimation(AppAnimation.smooth) { introCompleted = true }
                }
                .transition(.opacity)
            }
        }
        // «Начать поездку» (с карты и «Главной»): вид поездки, гостю — вход.
        .sheet(isPresented: $router.showsTripStart, onDismiss: runPendingTrip) {
            TripStartSheet { pendingTripActivity = $0 }
                .environment(session)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $router.showsRecording) {
            TripRecordingView(environment: environment)
                .environment(recorder)
                .environment(liveShare)
                .environment(session)
                .environment(sync)
                .environment(species)
                .environment(reactions)
                .environment(avatars)
                .environment(rules)
        }
        // Ссылка-приглашение из QR-кода или сообщения — профиль человека; ссылка на место или обсуждение.
        .onOpenURL { url in
            if let username = InviteLink.username(from: url) {
                profileLink = ProfileLink(username: username)
            } else if let threadID = ThreadLink.threadID(from: url) {
                threadLink = ThreadLinkItem(id: threadID)
            } else if let placeID = PlaceLink.placeID(from: url) {
                placeLink = PlaceSelection(id: placeID)
            } else if let tripID = TripLink.tripID(from: url) {
                tripLink = TripLinkItem(id: tripID)
            } else if let key = CommentsLink.key(from: url) {
                commentsLink = CommentsLinkItem(key: key)
            } else if let packingID = PackingLink.packingID(from: url) {
                packingLink = PackingLinkItem(id: packingID)
            } else if LiveLink.matches(url) {
                // «Сейчас на выезде» — на «Главной».
                router.selection = .home
            } else if let token = TripInviteLink.token(from: url) {
                pendingTripInvite = token
                Task { await acceptPendingTripInvite() }
            }
        }
        // Вошёл после ссылки-приглашения — принимаем.
        .task(id: session.profile?.id) { await acceptPendingTripInvite() }
        .alert(
            "trip.inviteLink.failed",
            isPresented: Binding(get: { inviteError != nil }, set: { if !$0 { inviteError = nil } })
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: inviteError ?? "")
        }
        .alert("trip.inviteLink.signIn.title", isPresented: $inviteNeedsSignIn) {
            Button("common.ok", role: .cancel) { router.selection = .profile }
        } message: {
            Text("trip.inviteLink.signIn")
        }
        .sheet(item: $packingLink) { link in
            NavigationStack {
                SharedPackingView(packingID: link.id, environment: environment)
            }
            .environment(session)
            .environment(avatars)
        }
        .sheet(item: $tripLink) { link in
            NavigationStack {
                TripDetailView(tripID: link.id, environment: environment)
            }
            .environment(session)
            .environment(species)
            .environment(sync)
            .environment(reactions)
            .environment(rules)
            .environment(avatars)
        }
        .sheet(item: $commentsLink) { link in
            NavigationStack {
                CommentsView(key: link.key)
            }
            .environment(session)
            .environment(reactions)
            .environment(avatars)
        }
        .sheet(item: $placeLink) { link in
            PlaceCardView(placeID: link.id, environment: environment)
                .environment(session)
                .environment(species)
                .environment(sync)
                .environment(reactions)
                .environment(avatars)
                .environment(rules)
                .environment(places)
        }
        .sheet(item: $threadLink) { link in
            NavigationStack {
                ThreadView(threadID: link.id, environment: environment)
            }
            .environment(session)
            .environment(reactions)
            .environment(avatars)
        }
        .sheet(item: $profileLink) { link in
            NavigationStack {
                if session.profile != nil {
                    UserProfileView(username: link.username, environment: environment)
                } else {
                    PlaceholderScreen(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "@" + link.username,
                        description: String(localized: "invite.signInToAdd")
                    )
                }
            }
            .environment(session)
            .environment(species)
            .environment(sync)
            .environment(reactions)
            .environment(avatars)
            .environment(rules)
        }
        // После первого входа — согласие с условиями, затем выбор username.
        .fullScreenCover(isPresented: $session.isOnboardingPresented) {
            Group {
                if session.needsConsent {
                    ConsentView()
                } else {
                    UsernameOnboardingView()
                }
            }
            .environment(session)
        }
        .environment(\.appEnvironment, environment)
        .environment(router)
        .environment(avatars)
        .environment(session)
        .environment(species)
        .environment(sync)
        .environment(recorder)
        .environment(liveShare)
        .environment(reactions)
        .environment(rules)
        .environment(lists)
        .environment(articles)
        .environment(places)
        .task { await session.start() }
        // Правила нужны без сети (карта, форма улова): сохранённая копия и обновление.
        .task { await rules.loadIfNeeded() }
        // Незаконченная запись поездки (приложение закрыли или система выгрузила) продолжается.
        .task {
            await recorder.restore()
            // Трансляция переживает выгрузку приложения, пока идёт запись; без записи — выключаем.
            await liveShare.restore()
            if !recorder.isActive && liveShare.isSharing {
                await liveShare.stop()
            }
        }
        // Офлайн-очередь: отправляем при появлении сети, возврате в приложение и входе.
        .task {
            for await _ in NetworkMonitor.becameAvailable() {
                sync.kick(force: true)
                lists.scheduleSync(after: .zero)
                Task { await PushRegistrar.shared.update(userID: session.profile?.id, backend: environment.backend) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                sync.kick(force: true)
                lists.scheduleSync(after: .zero)
                // Разрешение на уведомления могли дать в Настройках.
                Task { await PushRegistrar.shared.update(userID: session.profile?.id, backend: environment.backend) }
            case .background:
                background.didEnterBackground()
            default:
                break
            }
        }
        .onChange(of: session.profile?.id, initial: true) { previous, current in
            Task {
                await sync.refresh()
                sync.kick(force: true)
            }
            // Экипировка и чеклисты: свои у каждого аккаунта, у гостя — на телефоне.
            Task { await lists.switchUser(from: previous, to: current) }
            // Пуши: телефон получает уведомления вошедшего аккаунта (если разрешены).
            Task { await PushRegistrar.shared.update(userID: current, backend: environment.backend) }
        }
    }

    /// Запись начинается после закрытия листа: иначе полноэкранная запись
    /// не откроется поверх закрывающегося листа.
    /// Приглашение в поездку по ссылке: после входа — участник, сразу открываем поездку. Гостю —
    /// просьба войти (ссылка ждёт).
    private func acceptPendingTripInvite() async {
        guard !pendingTripInvite.isEmpty else { return }
        guard session.profile != nil, let backend = environment.backend else {
            if case .guest = session.state { inviteNeedsSignIn = true }
            return
        }
        let token = pendingTripInvite
        pendingTripInvite = ""
        do {
            let tripID = try await backend.acceptTripInviteLink(token)
            tripLink = TripLinkItem(id: tripID)
        } catch {
            inviteError = CommunityMessage.text(for: error)
        }
    }

    private func runPendingTrip() {
        guard let activity = pendingTripActivity else { return }
        pendingTripActivity = nil
        Task {
            await recorder.start(activity: activity)
            router.showsRecording = true
        }
    }
}

#Preview {
    RootView(environment: .preview, background: BackgroundSync(environment: .preview))
}

/// Обсуждение, открытое по ссылке из пуша.
struct ThreadLinkItem: Identifiable, Hashable {
    let id: UUID
}

/// Поездка, открытая по ссылке из пуша.
struct TripLinkItem: Identifiable, Hashable {
    let id: UUID
}

/// Общие сборы, открытые по ссылке из пуша-приглашения.
struct PackingLinkItem: Identifiable, Hashable {
    let id: UUID
}

/// Комментарии к посту, открытые по ссылке из пуша.
struct CommentsLinkItem: Identifiable, Hashable {
    let key: ReactionKey
    var id: String { "\(key.kind.rawValue)/\(key.id.uuidString)" }
}
