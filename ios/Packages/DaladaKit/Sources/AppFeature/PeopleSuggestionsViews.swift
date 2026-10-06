import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

/// «Возможно, вы знакомы»: друзья друзей и те, кто отчитывался в ваших местах. «Добавить» —
/// запрос в друзья, смахнуть — больше не подсказывать. Пусто — секции нет. Загружает экран, где
/// секция стоит (`load`): у пустой секции `task` не срабатывает.
struct PeopleSuggestionsSection: View {
    let environment: AppEnvironment
    @Binding var suggestions: [FriendSuggestion]

    @State private var requested: Set<UUID> = []

    static func load(_ environment: AppEnvironment, limit: Int = 5) async -> [FriendSuggestion]? {
        try? await environment.backend?.peopleYouMayKnow(limit: limit)
    }

    var body: some View {
        Group {
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions) { suggestion in
                        row(suggestion)
                            .swipeActions(edge: .trailing) {
                                Button("friends.suggestion.hide", systemImage: "eye.slash") {
                                    Task { await dismiss(suggestion) }
                                }
                            }
                    }
                } header: {
                    Text("friends.suggestions")
                } footer: {
                    Text("friends.suggestions.footer")
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ suggestion: FriendSuggestion) -> some View {
        HStack(spacing: AppSpacing.md) {
            NavigationLink {
                if let username = suggestion.username {
                    UserProfileView(username: username, environment: environment)
                }
            } label: {
                HStack(spacing: AppSpacing.md) {
                    PersonAvatar(name: suggestion.displayName ?? suggestion.username, path: suggestion.avatarPath)
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(verbatim: suggestion.displayName ?? suggestion.username.map { "@" + $0 } ?? "")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        Text(verbatim: reason(suggestion))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            if requested.contains(suggestion.id) {
                Label("friends.suggestion.requested", systemImage: "clock")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                Button("friends.suggestion.add") {
                    Task { await add(suggestion) }
                }
                .buttonStyle(.bordered)
                .font(AppTypography.bodySmall)
            }
        }
    }

    /// «Общих друзей: 2 · общих мест: 1».
    private func reason(_ suggestion: FriendSuggestion) -> String {
        var parts: [String] = []
        if suggestion.mutualFriends > 0 {
            parts.append(String(localized: "friends.suggestion.mutual \(suggestion.mutualFriends)"))
        }
        if suggestion.sharedPlaces > 0 {
            parts.append(String(localized: "friends.suggestion.places \(suggestion.sharedPlaces)"))
        }
        return parts.joined(separator: " · ")
    }

    private func add(_ suggestion: FriendSuggestion) async {
        guard let backend = environment.backend else { return }
        if (try? await backend.sendFriendRequest(to: suggestion.id)) != nil {
            requested.insert(suggestion.id)
        }
    }

    private func dismiss(_ suggestion: FriendSuggestion) async {
        suggestions.removeAll { $0.id == suggestion.id }
        try? await environment.backend?.dismissFriendSuggestion(suggestion.id)
    }
}
