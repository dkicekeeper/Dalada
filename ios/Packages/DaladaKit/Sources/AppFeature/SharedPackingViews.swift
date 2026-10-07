import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import Persistence
import SwiftUI

// MARK: - Список

/// «Общие сборы»: свои и куда пригласили друзья, с прогрессом. «+» — поделиться своими сборами.
struct SharedPackingsView: View {
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @State private var packings: [SharedPackingSummary] = []
    @State private var isLoaded = false
    @State private var showsShare = false
    @State private var opened: UUID?

    var body: some View {
        Group {
            if packings.isEmpty && isLoaded {
                EmptyStateView(
                    icon: "person.2.badge.gearshape",
                    title: String(localized: "sharedPacking.empty.title"),
                    description: String(localized: "sharedPacking.empty"),
                    actionTitle: session.profile != nil ? String(localized: "sharedPacking.share") : nil,
                    action: { showsShare = true }
                )
            } else {
                List(packings) { packing in
                    NavigationLink {
                        SharedPackingView(packingID: packing.id, environment: environment)
                    } label: {
                        SharedPackingRow(packing: packing)
                    }
                }
            }
        }
        .navigationTitle("sharedPacking.title")
        .navigationDestination(item: $opened) { id in
            SharedPackingView(packingID: id, environment: environment)
        }
        .toolbar {
            if session.profile != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsShare = true
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel(Text("sharedPacking.share"))
                    }
                }
            }
        }
        .sheet(isPresented: $showsShare, onDismiss: { Task { await load() } }) {
            SharePackingSheet(environment: environment) { id in
                opened = id
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    /// С сервера, а без сети — последний сохранённый список.
    private func load() async {
        defer { isLoaded = true }
        guard let userID = session.profile?.id else { return }
        let key = CacheKey.sharedPackings(userID)
        if let backend = environment.backend, let loaded = try? await backend.mySharedPackings() {
            packings = loaded
            try? await environment.cache.save(loaded, for: key)
        } else if packings.isEmpty, let cached = try? await environment.cache.load([SharedPackingSummary].self, for: key) {
            packings = cached
        }
    }
}

struct SharedPackingRow: View {
    let packing: SharedPackingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(verbatim: packing.title)
                .font(AppTypography.bodyEmphasis)
            Text(verbatim: subtitle)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            if packing.itemsCount > 0 {
                LinearProgressBar(value: Double(packing.doneCount) / Double(packing.itemsCount))
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let day = packing.tripDate {
            parts.append(day.date().formatted(date: .abbreviated, time: .omitted))
        }
        if !packing.isOwn, let owner = packing.ownerName {
            parts.append(String(localized: "sharedPacking.from \(owner)"))
        }
        parts.append(String(localized: "sharedPacking.progress \(packing.doneCount) \(packing.itemsCount)"))
        return parts.joined(separator: " · ")
    }
}

// MARK: - Поделиться

/// Поделиться сборами: выбрать свои сборы или чеклист, затем друзей.
struct SharePackingSheet: View {
    let environment: AppEnvironment
    let onShared: @MainActor (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(ListsStore.self) private var lists
    @State private var chosen: Checklist?
    @State private var friends: Set<UUID> = []
    @State private var isSharing = false
    @State private var errorText: String?

    /// `preselected` — сразу эти сборы (из экрана чеклиста), без выбора списка.
    init(environment: AppEnvironment, preselected: Checklist? = nil, onShared: @escaping @MainActor (UUID) -> Void) {
        self.environment = environment
        self.onShared = onShared
        _chosen = State(initialValue: preselected)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let chosen, let userID = session.profile?.id {
                    FriendPickerView(environment: environment, userID: userID, selection: $friends, limit: 20)
                        .navigationTitle(Text(verbatim: chosen.title))
                        .safeAreaInset(edge: .bottom) {
                            Text("sharedPacking.pickHint")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .screenPadding()
                                .padding(.vertical, AppSpacing.sm)
                        }
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                if isSharing {
                                    ProgressView()
                                } else {
                                    Button("sharedPacking.shareShort") {
                                        Task { await share(chosen) }
                                    }
                                    .disabled(friends.isEmpty)
                                }
                            }
                        }
                } else {
                    listPicker
                        .navigationTitle("sharedPacking.pickList")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
            .alert(
                "sharedPacking.failed",
                isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
            ) {
                Button("common.ok") {}
            } message: {
                Text(verbatim: errorText ?? "")
            }
        }
    }

    private var listPicker: some View {
        let candidates = lists.packingLists + lists.ownLists
        return Group {
            if candidates.isEmpty {
                EmptyStateView(
                    icon: "checklist",
                    title: String(localized: "sharedPacking.noLists.title"),
                    description: String(localized: "sharedPacking.noLists")
                )
            } else {
                List(candidates) { checklist in
                    Button {
                        chosen = checklist
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(verbatim: checklist.title)
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(AppColors.textPrimary)
                            Text("sharedPacking.itemsCount \(checklist.items.count)")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func share(_ checklist: Checklist) async {
        guard let backend = environment.backend else {
            errorText = String(localized: "own.error.offline")
            return
        }
        isSharing = true
        defer { isSharing = false }
        do {
            let id = try await backend.sharePacking(
                title: checklist.title,
                tripDate: checklist.tripDate,
                items: SharedPacking.items(from: checklist),
                members: Array(friends)
            )
            dismiss()
            onShared(id)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Общие сборы

/// Общие сборы: по категориям; у пункта — «собрано» и кто берёт («Возьму»). Добавить пункт может
/// любой участник; убрать — автор сборов или кто добавил. Обновляется раз в 30 секунд, пока открыт.
/// Без сети — последнее, что загрузилось (только посмотреть: отметки меняются на сервере).
struct SharedPackingView: View {
    let packingID: UUID
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var items: [SharedPackingItem] = []
    @State private var members: [SharedPackingMember] = []
    @State private var isLoaded = false
    @State private var newTitle = ""
    @State private var confirmsLeave = false
    @State private var errorText: String?

    private var me: UUID? { session.profile?.id }
    private var isOwner: Bool { members.first { $0.isOwner }?.userID == me }
    /// Автор удаляет сборы у всех, участник — выходит из них.
    private var leaveTitle: LocalizedStringKey {
        LocalizedStringKey(isOwner ? "sharedPacking.delete" : "sharedPacking.leave")
    }

    var body: some View {
        List {
            if !members.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.md) {
                            ForEach(members) { member in
                                VStack(spacing: AppSpacing.xxs) {
                                    PersonAvatar(name: member.name, path: member.avatarPath, size: AppIconSize.Tile.xs)
                                    Text(verbatim: shortName(member))
                                        .font(AppTypography.caption)
                                        .lineLimit(1)
                                }
                                .frame(width: AppIconSize.Tile.xxxl)
                            }
                        }
                    }
                    if !items.isEmpty {
                        let done = items.filter(\.done).count
                        LinearProgressBar(value: Double(done) / Double(items.count))
                        Text("sharedPacking.summary \(done) \(items.count) \(SharedPacking.unassignedCount(items))")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            ForEach(SharedPacking.grouped(items), id: \.category) { group in
                Section {
                    ForEach(group.items) { item in
                        row(item)
                            .swipeActions(edge: .trailing) {
                                if canDelete(item) {
                                    Button("sharedPacking.deleteItem", systemImage: "trash", role: .destructive) {
                                        Task { await act { try await $0.deletePackingItem(item.id) } }
                                    }
                                }
                            }
                    }
                } header: {
                    if let category = group.category {
                        Label(LocalizedStringKey(category.titleKey), systemImage: category.systemImage)
                    } else {
                        Text("sharedPacking.otherItems")
                    }
                }
            }
            Section {
                HStack {
                    TextField("sharedPacking.addPlaceholder", text: $newTitle)
                        .submitLabel(.done)
                        .onSubmit { Task { await addItem() } }
                    Button {
                        Task { await addItem() }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .accessibilityLabel(Text("sharedPacking.add"))
                    }
                    .buttonStyle(.borderless)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("sharedPacking.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(leaveTitle, systemImage: isOwner ? "trash" : "rectangle.portrait.and.arrow.right", role: .destructive) {
                        confirmsLeave = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel(Text("sharedPacking.menu"))
                }
            }
        }
        .confirmationDialog(
            LocalizedStringKey(isOwner ? "sharedPacking.deleteConfirm" : "sharedPacking.leaveConfirm"),
            isPresented: $confirmsLeave,
            titleVisibility: .visible
        ) {
            Button(leaveTitle, role: .destructive) {
                Task {
                    await act { [packingID] in try await $0.leaveSharedPacking(packingID) }
                    if let me { try? await environment.cache.remove(CacheKey.sharedPacking(packingID, user: me)) }
                    dismiss()
                }
            }
        }
        .alert(
            "sharedPacking.failed",
            isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
        ) {
            Button("common.ok") {}
        } message: {
            Text(verbatim: errorText ?? "")
        }
        .refreshable { await load() }
        .task {
            // Пока экран открыт — раз в 30 секунд: видно, кто что взял.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func row(_ item: SharedPackingItem) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                Task { await act { try await $0.setPackingItemDone(item.id, done: !item.done) } }
            } label: {
                SelectionIndicator(isSelected: item.done, tint: AppColors.success)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(LocalizedStringKey(item.done ? "sharedPacking.packed" : "sharedPacking.notPacked")))
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: item.title)
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? AppColors.textSecondary : AppColors.textPrimary)
                if let assignee = item.assigneeID, assignee != me {
                    Text("sharedPacking.takenBy \(name(of: assignee))")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer(minLength: 0)
            assigneeButton(item)
        }
    }

    @ViewBuilder
    private func assigneeButton(_ item: SharedPackingItem) -> some View {
        if item.assigneeID == nil {
            Button("sharedPacking.take") {
                Task { await act { try await $0.takePackingItem(item.id, take: true) } }
            }
            .font(AppTypography.bodySmall)
            .buttonStyle(.borderless)
        } else if item.assigneeID == me {
            Button {
                Task { await act { try await $0.takePackingItem(item.id, take: false) } }
            } label: {
                Label("sharedPacking.mine", systemImage: "hand.raised.fill")
                    .font(AppTypography.bodySmall)
            }
            .buttonStyle(.borderless)
        }
    }

    private func canDelete(_ item: SharedPackingItem) -> Bool {
        isOwner || item.createdBy == me
    }

    private func name(of userID: UUID) -> String {
        members.first { $0.userID == userID }?.name ?? String(localized: "profile.noName")
    }

    private func shortName(_ member: SharedPackingMember) -> String {
        if let first = member.displayName?.split(separator: " ").first { return String(first) }
        return member.username.map { "@" + $0 } ?? String(localized: "profile.noName")
    }

    private func load() async {
        defer { isLoaded = true }
        let key = me.map { CacheKey.sharedPacking(packingID, user: $0) }
        if let backend = environment.backend {
            async let loadedItems = try? backend.sharedPackingItems(packingID)
            async let loadedMembers = try? backend.sharedPackingMembers(packingID)
            if let loadedItems = await loadedItems, let loadedMembers = await loadedMembers {
                items = loadedItems
                members = loadedMembers
                if let key {
                    try? await environment.cache.save(SharedPackingSnapshot(items: loadedItems, members: loadedMembers), for: key)
                }
                return
            }
        }
        if items.isEmpty, members.isEmpty, let key,
           let cached = try? await environment.cache.load(SharedPackingSnapshot.self, for: key) {
            items = cached.items
            members = cached.members
        }
    }

    private func addItem() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newTitle = ""
        await act { [packingID] in _ = try await $0.addPackingItem(packingID, title: title) }
    }

    /// Действие на сервере, затем свежие пункты; ошибка — в алерт.
    private func act(_ action: @escaping @Sendable (BackendClient) async throws -> Void) async {
        guard let backend = environment.backend else {
            errorText = String(localized: "own.error.offline")
            return
        }
        do {
            try await action(backend)
        } catch {
            errorText = error.localizedDescription
        }
        await load()
    }
}

/// Общие сборы для кэша: пункты и участники вместе.
private struct SharedPackingSnapshot: Codable, Sendable {
    let items: [SharedPackingItem]
    let members: [SharedPackingMember]
}
