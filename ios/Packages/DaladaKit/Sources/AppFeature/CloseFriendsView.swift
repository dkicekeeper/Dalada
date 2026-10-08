import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

/// «Близкие друзья»: кому видно то, что отмечено «Близкие». Список видите только вы; люди не узнают,
/// что в нём. Нажатие на друга — добавить или убрать.
struct CloseFriendsView: View {
    let environment: AppEnvironment

    @State private var friends: [Friend] = []
    @State private var close: Set<UUID> = []
    @State private var isLoaded = false
    @State private var errorText: String?

    var body: some View {
        List {
            if friends.isEmpty && isLoaded {
                EmptyState(
                    icon: "person.2",
                    title: String(localized: "closeFriends.empty.title"),
                    description: String(localized: "closeFriends.empty")
                )
                .listRowBackground(Color.clear)
            } else if !isLoaded {
                Section {
                    ForEach(0..<5, id: \.self) { _ in
                        PersonRowSkeleton()
                    }
                }
            } else {
                Section {
                    ForEach(friends) { friend in
                        Button {
                            Task { await toggle(friend.id) }
                        } label: {
                            PersonRow(displayName: friend.displayName, username: friend.username, avatarPath: friend.avatarPath) {
                                Image(systemName: close.contains(friend.id) ? "star.circle.fill" : "circle")
                                    .foregroundStyle(close.contains(friend.id) ? AppColors.accent : AppColors.textTertiary)
                                    .font(AppTypography.bodyEmphasis)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(close.contains(friend.id) ? .isSelected : [])
                    }
                } footer: {
                    Text("closeFriends.footer")
                }
            }
        }
        // Друзья проявляются на месте скелетонов.
        .animation(AppAnimation.smooth, value: isLoaded)
        .navigationTitle("closeFriends.title")
        .task { await load() }
        .alert(
            "own.error.title",
            isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
        ) {
            Button("common.ok") {}
        } message: {
            Text(verbatim: errorText ?? "")
        }
    }

    private func load() async {
        defer { isLoaded = true }
        guard let backend = environment.backend else { return }
        async let loadedFriends = try? backend.myFriends()
        async let loadedClose = try? backend.closeFriendIDs()
        friends = await loadedFriends ?? []
        close = await loadedClose ?? []
    }

    private func toggle(_ id: UUID) async {
        guard let backend = environment.backend else {
            errorText = String(localized: "own.error.offline")
            return
        }
        let wasClose = close.contains(id)
        // Сразу на экране, при ошибке — назад.
        if wasClose { close.remove(id) } else { close.insert(id) }
        do {
            if wasClose {
                try await backend.removeCloseFriend(id)
            } else {
                try await backend.addCloseFriend(id)
            }
        } catch {
            if wasClose { close.insert(id) } else { close.remove(id) }
            errorText = error.localizedDescription
        }
    }
}
