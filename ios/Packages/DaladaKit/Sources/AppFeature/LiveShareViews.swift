import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import MapEngine
import SwiftUI

// MARK: - Своя трансляция

/// Трансляция геопозиции друзьям во время записи поездки: включить (кому), присылать точки, выключить.
/// Точки приходят от `TripRecorder`; отправка — по `LiveSharePolicy` (раз в минуту при движении,
/// раз в 5 минут на месте). Финиш или удаление поездки выключают трансляцию.
@MainActor
@Observable
final class LiveShareController {
    private let backend: BackendClient?
    private(set) var share: MyLiveShare?
    private(set) var isWorking = false
    var errorText: String?

    @ObservationIgnored private var lastPoint: GeoPoint?
    @ObservationIgnored private var lastSentAt: Date?
    @ObservationIgnored private var isSending = false

    init(backend: BackendClient?) {
        self.backend = backend
    }

    var isSharing: Bool { share?.isActive(at: .now) ?? false }

    func start(viewers: Set<UUID>, current: GeoPoint?) async {
        guard let backend, !viewers.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let until = try await backend.startLiveShare(viewers: Array(viewers))
            share = MyLiveShare(startedAt: .now, expiresAt: until, updatedAt: nil, viewerIDs: Array(viewers))
            lastPoint = nil
            lastSentAt = nil
            if let current {
                await send(current, accuracy: nil, at: .now)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    func stop() async {
        guard share != nil else { return }
        share = nil
        lastPoint = nil
        lastSentAt = nil
        try? await backend?.stopLiveShare()
    }

    /// После запуска приложения: трансляция могла идти до выгрузки.
    func restore() async {
        share = try? await backend?.myLiveShare()
    }

    /// Новая точка записи поездки.
    func didRecord(_ point: GeoPoint, accuracy: Double?, at date: Date) {
        guard isSharing, !isSending,
              LiveSharePolicy.shouldSend(lastPoint: lastPoint, lastSentAt: lastSentAt, point: point, at: date)
        else { return }
        Task { await send(point, accuracy: accuracy, at: date) }
    }

    private func send(_ point: GeoPoint, accuracy: Double?, at date: Date) async {
        guard let backend else { return }
        isSending = true
        defer { isSending = false }
        do {
            if try await backend.updateLiveLocation(point, accuracy: accuracy) {
                lastPoint = point
                lastSentAt = date
                share?.updatedAt = date
            } else {
                // Кончилась или выключена с другого устройства.
                share = nil
            }
        } catch {
            // Нет сети — попробуем со следующей точкой.
        }
    }
}

/// Строка на экране записи: «Показывать друзьям, где я» или «Видят 3 друга · до 22:40 · Выключить».
struct LiveShareRow: View {
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @Environment(TripRecorder.self) private var recorder
    @Environment(LiveShareController.self) private var live
    @State private var showsPicker = false
    @State private var picked: Set<UUID> = []

    var body: some View {
        if let userID = session.profile?.id {
            Group {
                if let share = live.share, live.isSharing {
                    HStack(spacing: AppSpacing.sm) {
                        // Трансляция идёт — значок «дышит» (DesignKit; без движения под Reduce Motion).
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(AppColors.success)
                            .symbolPulse(.breathe)
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text("live.sharing \(share.viewerIDs.count)")
                                .font(AppTypography.bodySmall)
                            Text("live.until \(share.expiresAt.formatted(date: .omitted, time: .shortened))")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Button("live.stop", role: .destructive) {
                            Task { await live.stop() }
                        }
                        .font(AppTypography.bodySmall)
                        .buttonStyle(.borderless)
                    }
                } else {
                    Button {
                        picked = []
                        showsPicker = true
                    } label: {
                        Label("live.start", systemImage: "location.circle")
                            .font(AppTypography.bodySmall)
                    }
                    .buttonStyle(.borderless)
                    .disabled(live.isWorking || environment.backend == nil)
                }
            }
            .sheet(isPresented: $showsPicker) {
                NavigationStack {
                    FriendPickerView(
                        environment: environment,
                        userID: userID,
                        selection: $picked,
                        limit: 50
                    )
                    .navigationTitle("live.pickTitle")
                    .safeAreaInset(edge: .bottom) {
                        Text("live.pickHint")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .screenPadding()
                            .padding(.vertical, AppSpacing.sm)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("common.cancel") { showsPicker = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("live.startShort") {
                                showsPicker = false
                                Task { await live.start(viewers: picked, current: recorder.track.last) }
                            }
                            .disabled(picked.isEmpty)
                        }
                    }
                }
            }
            .alert(
                "live.failed",
                isPresented: Binding(get: { live.errorText != nil }, set: { if !$0 { live.errorText = nil } })
            ) {
                Button("common.ok") {}
            } message: {
                Text(verbatim: live.errorText ?? "")
            }
        }
    }
}

// MARK: - Друзья на выезде

/// «Сейчас на выезде» на «Главной»: друзья, которые показывают мне, где они. Обновляется раз в
/// минуту, пока экран открыт. Нажатие — карта с последней точкой и «Маршрут».
struct FriendsLiveSection: View {
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @State private var friends: [FriendLiveLocation] = []
    @State private var opened: FriendLiveLocation?

    var body: some View {
        Group {
            if !friends.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    SectionHeader(String(localized: "live.friendsTitle"))
                    ForEach(friends) { friend in
                        Button {
                            opened = friend
                        } label: {
                            FriendLiveRow(friend: friend)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .cardContentPadding()
                .cardStyle()
            }
        }
        .task(id: session.profile?.id) {
            // Пока экран на виду — раз в минуту.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .sheet(item: $opened) { friend in
            FriendLiveMapView(friend: friend, environment: environment)
        }
    }

    private func load() async {
        guard session.profile != nil, let backend = environment.backend else {
            friends = []
            return
        }
        if let loaded = try? await backend.friendsLiveLocations() {
            friends = loaded
        }
    }
}

struct FriendLiveRow: View {
    let friend: FriendLiveLocation

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            PersonAvatar(name: friend.name, path: friend.avatarPath, size: AppIconSize.xxl)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: friend.name ?? String(localized: "profile.noName"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                Text(verbatim: LiveText.status(friend))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: 0)
            DisclosureChevron()
        }
        .contentShape(Rectangle())
    }
}

/// Последняя точка друга на карте; «Маршрут» — к ней во внешнем навигаторе.
struct FriendLiveMapView: View {
    let friend: FriendLiveLocation
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if let point = friend.coordinate {
                    DaladaMapView(
                        styleURL: environment.config.mapStyleURL,
                        initialCenter: point,
                        initialZoom: 13,
                        draftPin: point
                    )
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl))
                } else {
                    EmptyState(
                        icon: friend.inPrivacyZone ? "house.circle" : "location.slash",
                        title: String(localized: friend.inPrivacyZone ? "live.hiddenTitle" : "live.noPointTitle"),
                        description: String(localized: friend.inPrivacyZone ? "live.hidden" : "live.noPoint")
                    )
                }
                Text(verbatim: LiveText.status(friend))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                if let accuracy = friend.accuracyM, accuracy >= 50 {
                    Text("live.accuracy \(String(Int(accuracy.rounded())))")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                if let point = friend.coordinate {
                    RouteButton(destination: point)
                }
                Spacer(minLength: 0)
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
            .navigationTitle(Text(verbatim: friend.name ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

enum LiveText {
    /// «Обновлено 5 мин назад · до 22:40» или «Ещё не прислал точку».
    static func status(_ friend: FriendLiveLocation) -> String {
        let until = String(localized: "live.until \(friend.expiresAt.formatted(date: .omitted, time: .shortened))")
        guard let updated = friend.updatedAt else {
            return String(localized: "live.noPointShort") + " · " + until
        }
        let ago = updated.formatted(.relative(presentation: .named))
        return String(localized: "live.updated \(ago)") + " · " + until
    }
}
