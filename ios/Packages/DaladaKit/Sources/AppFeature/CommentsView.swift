import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

/// Кнопка «Комментарии» под постом: значок и число (пока комментариев нет — «Комментировать»);
/// открывает комментарии листом. `isProminent` — кнопка во всю ширину для экрана самого поста.
struct CommentsButton: View {
    let key: ReactionKey
    var isProminent = false

    @Environment(ReactionStore.self) private var reactions
    @State private var showsComments = false

    var body: some View {
        let count = reactions.commentCount(for: key)
        Group {
            if isProminent {
                Button {
                    showsComments = true
                } label: {
                    Label {
                        if count > 0 {
                            Text("comments.button \(count)")
                        } else {
                            Text("comments.button.zero")
                        }
                    } icon: {
                        Image(systemName: "bubble.left.and.bubble.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .secondaryButton()
            } else {
                Button {
                    showsComments = true
                } label: {
                    Label {
                        if count > 0 {
                            Text(verbatim: "\(count)")
                        } else {
                            Text("comments.button.zero")
                        }
                    } icon: {
                        Image(systemName: "bubble.left")
                    }
                    .foregroundStyle(AppColors.textSecondary)
                    // Зона нажатия — не меньше 44 pt, как советует Apple.
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .font(AppTypography.bodySmall)
            }
        }
        .accessibilityLabel(Text("comments.accessibility \(count)"))
        .sheet(isPresented: $showsComments) {
            NavigationStack {
                CommentsView(key: key)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// Комментарии поста (поездки, отчёта, отзыва): список, поле ввода. Удалить можно свой комментарий
/// и любой под своим постом (смахнуть влево); у чужих — «Пожаловаться» и «Заблокировать».
struct CommentsView: View {
    let key: ReactionKey

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(ReactionStore.self) private var reactions
    @State private var comments: [PostComment] = []
    @State private var isLoaded = false
    @State private var loadError: String?
    @State private var text = ""
    @State private var draftID = UUID()
    @State private var isSending = false
    @State private var sendError: String?
    @State private var deleteError: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        List {
            if comments.isEmpty {
                if !isLoaded {
                    ForEach(0..<3, id: \.self) { _ in
                        CommentRowSkeleton()
                            .listRowSeparator(.hidden)
                    }
                } else {
                    Text(verbatim: loadError ?? String(localized: "comments.empty"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                        .listRowSeparator(.hidden)
                }
            }
            ForEach(comments) { comment in
                commentRow(comment)
                    .swipeActions(edge: .trailing) {
                        if comment.canDelete {
                            Button("comments.delete", systemImage: "trash", role: .destructive) {
                                Task { await delete(comment) }
                            }
                        }
                    }
                    .contextMenu {
                        if comment.canDelete {
                            Button("comments.delete", systemImage: "trash", role: .destructive) {
                                Task { await delete(comment) }
                            }
                        }
                    }
            }
        }
        .listStyle(.plain)
        .navigationTitle("comments.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("common.close", systemImage: "xmark") { dismiss() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .safeAreaBar(edge: .bottom) {
            composer
        }
        .alert("comments.deleteFailed", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: deleteError ?? "")
        }
    }

    /// Поле комментария из DesignKit: стекло над списком, кнопка отправки внутри. Гостю — то же
    /// поле, выключенное, с подсказкой войти.
    @ViewBuilder
    private var composer: some View {
        Group {
            if session.profile == nil {
                MessageComposer(text: .constant(""), placeholder: String(localized: "comments.signIn")) {}
                    .disabled(true)
            } else {
                MessageComposer(
                    text: $text,
                    placeholder: String(localized: "comments.placeholder"),
                    isSending: isSending,
                    canSend: draft.isValid,
                    errorMessage: sendError,
                    focus: $isFocused
                ) {
                    Task { await send() }
                }
            }
        }
        .screenPadding()
        .padding(.bottom, AppSpacing.sm)
    }

    /// Комментарий: строка DesignKit, аватар и меню «Пожаловаться» / «Заблокировать» — свои.
    private func commentRow(_ comment: PostComment) -> some View {
        let isOwn = comment.author.id == session.profile?.id
        return CommentRow(
            author: isOwn ? String(localized: "report.you") : comment.author.label,
            date: comment.createdAt,
            text: AttributedString(comment.body),
            avatar: PersonAvatar(
                name: comment.author.displayName ?? comment.author.username,
                path: comment.author.avatarPath,
                size: CommentRowMetrics.avatarSize
            )
        ) {
            if !isOwn {
                ModerationMenu(target: .comment, targetID: comment.id, author: comment.author) {
                    Task { await load() }
                }
            }
        }
    }

    private var draft: CommentDraft {
        CommentDraft(id: draftID, target: key, body: text)
    }

    private func load() async {
        guard let backend = session.backend else {
            isLoaded = true
            return
        }
        do {
            comments = try await backend.postComments(key)
            loadError = nil
            reactions.setCommentCount(comments.count, for: key)
        } catch is CancellationError {
            return
        } catch {
            loadError = CommunityMessage.text(for: error)
        }
        isLoaded = true
    }

    private func send() async {
        guard let backend = session.backend, draft.isValid else { return }
        isSending = true
        sendError = nil
        defer { isSending = false }
        do {
            try await backend.addComment(draft)
            text = ""
            draftID = UUID()
            await load()
        } catch {
            sendError = CommunityMessage.text(for: error)
        }
    }

    private func delete(_ comment: PostComment) async {
        guard let backend = session.backend else { return }
        do {
            try await backend.deleteComment(comment.id)
            await load()
        } catch {
            deleteError = CommunityMessage.text(for: error)
        }
    }
}
