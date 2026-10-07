import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import Persistence
import SwiftUI

// MARK: - Друзья

/// Свои друзья: сеть, без неё — сохранённый список (отметить друзей на финише поездки без сети).
struct FriendsLoader {
    let environment: AppEnvironment
    let userID: UUID

    func load() async -> [Friend] {
        let key = CacheKey.friends(userID)
        if let backend = environment.backend, let friends = try? await backend.myFriends() {
            try? await environment.cache.save(friends, for: key)
            return friends
        }
        return (try? await environment.cache.load([Friend].self, for: key)) ?? []
    }
}

/// Выбор друзей для отметки в поездке: галочки, не больше `limit`. Уже отмеченных не показываем.
struct FriendPickerView: View {
    let environment: AppEnvironment
    let userID: UUID
    @Binding var selection: Set<UUID>
    var excluded: Set<UUID> = []
    var limit: Int = TripParticipants.limit

    @State private var friends: [Friend] = []
    @State private var isLoaded = false

    var body: some View {
        Group {
            if available.isEmpty && isLoaded {
                EmptyStateView(
                    icon: "person.2",
                    title: String(localized: "friendPicker.empty.title"),
                    description: String(localized: "friendPicker.empty.description")
                )
            } else {
                List {
                    Section {
                        ForEach(available) { friend in
                            row(friend)
                        }
                    } footer: {
                        Text("friendPicker.limit \(limit)")
                    }
                }
            }
        }
        .navigationTitle("trip.participants.tag")
        .task {
            friends = await FriendsLoader(environment: environment, userID: userID).load()
            isLoaded = true
        }
    }

    private var available: [Friend] {
        friends.filter { !excluded.contains($0.id) }
    }

    private func row(_ friend: Friend) -> some View {
        let isSelected = selection.contains(friend.id)
        let isFull = selection.count >= limit && !isSelected
        return Button {
            if isSelected {
                selection.remove(friend.id)
            } else if !isFull {
                selection.insert(friend.id)
            }
        } label: {
            HStack(spacing: AppSpacing.md) {
                SelectionIndicator(isSelected: isSelected, tint: AppColors.accent)
                PersonRow(displayName: friend.displayName, username: friend.username, avatarPath: friend.avatarPath)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFull)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Участники на странице поездки

/// Участники поездки. Автор отмечает друзей и убирает отметки; отмеченный принимает или отклоняет,
/// принявший может выйти. `onLeft` — поездка могла перестать быть видна (отклонил или вышел).
struct TripParticipantsSection: View {
    let tripID: UUID
    let isOwn: Bool
    let environment: AppEnvironment
    let onLeft: @MainActor () async -> Void

    @Environment(SessionStore.self) private var session
    @State private var participants: [TripParticipant] = []
    @State private var showsPicker = false
    @State private var picked: Set<UUID> = []
    @State private var isWorking = false
    @State private var actionError: String?
    @State private var showsActionError = false
    @State private var confirmsLeave = false
    @State private var showsInviteLink = false

    var body: some View {
        Group {
            if let mine = TripParticipants.mine(in: participants), mine.status == .pending {
                invitation
            }
            if isOwn && visible.isEmpty {
                // Никого не отметили — одна строка-кнопка вместо раздела с заголовком.
                tagButton
            } else if !visible.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    SectionHeaderView(String(localized: "trip.participants.title"), systemImage: "person.2")
                    ForEach(visible) { participant in
                        row(participant)
                    }
                    if isOwn {
                        tagButton
                    } else if let mine = TripParticipants.mine(in: participants), mine.status == .accepted {
                        Button("trip.participants.leave", role: .destructive) {
                            confirmsLeave = true
                        }
                        .font(AppTypography.bodySmall)
                    }
                }
            }
        }
        .task(id: tripID) { await load() }
        .sheet(isPresented: $showsPicker) {
            if let userID = session.profile?.id {
                NavigationStack {
                    FriendPickerView(
                        environment: environment,
                        userID: userID,
                        selection: $picked,
                        excluded: Set(participants.map(\.userID)),
                        limit: TripParticipants.limit - participants.count
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("common.cancel") { showsPicker = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("common.done") {
                                showsPicker = false
                                Task { await tag(picked) }
                            }
                            .disabled(picked.isEmpty)
                        }
                    }
                }
            }
        }
        .confirmationDialog("trip.participants.leave", isPresented: $confirmsLeave, titleVisibility: .visible) {
            Button("trip.participants.leave", role: .destructive) {
                Task { await respond(accept: false) }
            }
        } message: {
            Text("trip.participants.leaveConfirm")
        }
        .alert("trip.participants.failed", isPresented: $showsActionError) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: actionError ?? "")
        }
    }

    /// Себя-ждущего показываем приглашением, а не строкой списка.
    private var visible: [TripParticipant] {
        participants.filter { !($0.isMe && $0.status == .pending) }
    }

    /// «Отметить друзей» — компактной кнопкой: это нечастое действие, не повод для большой кнопки.
    /// «Отметить друзей» и «Пригласить по ссылке» — для тех, кого ещё нет в Dalada.
    private var tagButton: some View {
        HStack(spacing: AppSpacing.lg) {
            Button {
                picked = []
                showsPicker = true
            } label: {
                Label("trip.participants.tag", systemImage: "person.badge.plus")
                    .font(AppTypography.bodySmall)
            }
            Button {
                showsInviteLink = true
            } label: {
                Label("trip.inviteLink.button", systemImage: "link")
                    .font(AppTypography.bodySmall)
            }
            .sheet(isPresented: $showsInviteLink) {
                TripInviteLinkSheet(tripID: tripID, environment: environment)
            }
        }
        .buttonStyle(.borderless)
        .disabled(isWorking || participants.count >= TripParticipants.limit || environment.backend == nil)
    }

    private var invitation: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Label("trip.invitation.title", systemImage: "person.crop.circle.badge.questionmark")
                .font(AppTypography.bodyEmphasis)
            Text("trip.invitation.message")
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
            HStack(spacing: AppSpacing.md) {
                Button {
                    Task { await respond(accept: true) }
                } label: {
                    Text("trip.invitation.accept")
                        .frame(maxWidth: .infinity)
                }
                .primaryButton()
                Button {
                    Task { await respond(accept: false) }
                } label: {
                    Text("trip.invitation.decline")
                        .frame(maxWidth: .infinity)
                }
                .secondaryButton()
            }
            .disabled(isWorking)
        }
        .cardContentPadding()
        .cardStyle()
    }

    @ViewBuilder
    private func row(_ participant: TripParticipant) -> some View {
        PersonRow(displayName: participant.displayName, username: participant.username, avatarPath: participant.avatarPath) {
            if participant.status == .pending {
                Text("trip.participants.pending")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            if isOwn {
                Menu {
                    Button("trip.participants.remove", systemImage: "person.badge.minus", role: .destructive) {
                        Task { await untag(participant.userID) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("trip.participants.remove"))
                .disabled(isWorking)
            }
        }
    }

    private func load() async {
        guard let backend = environment.backend, session.profile != nil else { return }
        if let loaded = try? await backend.tripParticipants(tripID: tripID) {
            participants = loaded
        }
    }

    private func tag(_ ids: Set<UUID>) async {
        guard let backend = environment.backend, !ids.isEmpty else { return }
        await perform { try await backend.tagTripFriends(tripID: tripID, userIDs: Array(ids)) }
    }

    private func untag(_ userID: UUID) async {
        guard let backend = environment.backend else { return }
        await perform { try await backend.untagTripFriend(tripID: tripID, userID: userID) }
    }

    private func respond(accept: Bool) async {
        guard let backend = environment.backend else { return }
        await perform { try await backend.respondTripTag(tripID: tripID, accept: accept) }
        if !accept {
            await onLeft()
        }
    }

    private func perform(_ action: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await action()
            await load()
        } catch {
            actionError = error.localizedDescription
            showsActionError = true
        }
    }
}

// MARK: - Приглашения на «Главной»

/// «Вас отметили в поездке»: приглашения, на которые ещё нет ответа. Нажатие — страница поездки
/// (там «Принять» и «Отклонить»). Нет приглашений или сети — раздела нет.
struct TripInvitationsSection: View {
    let environment: AppEnvironment
    /// Меняется, когда «Главную» обновили: приглашения загружаются заново.
    var refreshID: Int = 0

    @Environment(SessionStore.self) private var session
    @State private var invitations: [TripInvitation] = []

    var body: some View {
        Group {
            if !invitations.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    SectionHeaderView(String(localized: "home.invitations.title"), systemImage: "person.2.badge.plus")
                    ForEach(invitations) { invitation in
                        NavigationLink {
                            TripDetailView(tripID: invitation.tripID, environment: environment)
                                .onDisappear { Task { await load() } }
                        } label: {
                            row(invitation)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task(id: TaskKey(user: session.profile?.id, refresh: refreshID)) { await load() }
    }

    private struct TaskKey: Equatable {
        let user: UUID?
        let refresh: Int
    }

    private func row(_ invitation: TripInvitation) -> some View {
        HStack(spacing: AppSpacing.md) {
            PersonAvatar(name: invitation.owner.displayName ?? invitation.owner.username, path: invitation.owner.avatarPath)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: invitation.title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(verbatim: hostLine(invitation))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            DisclosureChevron()
        }
        .cardContentPadding()
        .cardStyle()
    }

    private func hostLine(_ invitation: TripInvitation) -> String {
        let host = invitation.owner.username.map { "@" + $0 } ?? invitation.owner.displayName ?? ""
        let date = invitation.startedAt.formatted(.dateTime.day().month(.wide))
        return host.isEmpty ? date : host + " · " + date
    }

    private func load() async {
        guard let backend = environment.backend, session.profile != nil else {
            invitations = []
            return
        }
        if let loaded = try? await backend.myTripInvitations() {
            invitations = loaded
        }
    }
}

// MARK: - Приглашение по ссылке

/// «Пригласить по ссылке»: ссылка на страницу приглашения — для тех, у кого ещё нет Dalada. Открыл в
/// приложении после входа — участник поездки, а вам — запрос в друзья. Ссылка живёт 30 дней.
struct TripInviteLinkSheet: View {
    let tripID: UUID
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var link: URL?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: AppIconSize.Tile.sm))
                    .foregroundStyle(AppColors.accent)
                Text("trip.inviteLink.message")
                    .font(AppTypography.body)
                    .multilineTextAlignment(.center)
                if let link {
                    ShareLink(item: link, message: Text("trip.inviteLink.shareMessage")) {
                        Label("trip.inviteLink.send", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryButton()
                } else if let errorText {
                    Text(verbatim: errorText)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.destructive)
                        .multilineTextAlignment(.center)
                    Button("common.retry") {
                        Task { await load() }
                    }
                    .secondaryButton()
                } else {
                    ProgressView()
                }
                Text("trip.inviteLink.footer")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
            .navigationTitle("trip.inviteLink.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close", systemImage: "xmark") { dismiss() }
                }
            }
            .task { await load() }
        }
        .presentationDetents([.medium])
    }

    private func load() async {
        errorText = nil
        guard let backend = environment.backend else {
            errorText = String(localized: "own.error.offline")
            return
        }
        do {
            link = WebLink.tripInvite(try await backend.tripInviteLink(tripID))
        } catch {
            errorText = CommunityMessage.text(for: error)
        }
    }
}
