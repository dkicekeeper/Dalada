import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

// MARK: - Меню «…» у чужого контента

/// «…» у чужого отзыва, ответа, отчёта, места, поездки: «Пожаловаться» и «Заблокировать автора».
/// Гостю не показывается.
struct ModerationMenu: View {
    let target: ReportTarget
    let targetID: UUID
    /// Автор — для «Заблокировать»; `nil` — пункт не показывается.
    var author: FeedAuthor?
    /// Вид кнопки: «…» в строке или «…» в кружке для панели навигации.
    var isToolbar = false
    /// После блокировки: перечитать экран или закрыть его.
    var onBlocked: (@MainActor () -> Void)?

    @Environment(SessionStore.self) private var session
    @State private var reports = false
    @State private var confirmsBlock = false
    @State private var blockError: String?
    @State private var showsBlockError = false

    var body: some View {
        if session.profile != nil {
            Menu {
                Button("moderation.report", systemImage: "flag") {
                    reports = true
                }
                if let author, author.id != session.profile?.id {
                    Button("moderation.block \(author.label)", systemImage: "hand.raised", role: .destructive) {
                        confirmsBlock = true
                    }
                }
            } label: {
                Image(systemName: isToolbar ? "ellipsis.circle" : "ellipsis")
                    .font(isToolbar ? nil : AppTypography.caption)
                    .foregroundStyle(isToolbar ? AppColors.accent : AppColors.textTertiary)
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
                    .accessibilityLabel(Text("moderation.actions"))
            }
            .sheet(isPresented: $reports) {
                ReportView(target: target, targetID: targetID)
                    .environment(session)
            }
            .confirmationDialog("person.blockConfirm", isPresented: $confirmsBlock, titleVisibility: .visible) {
                Button("person.block", role: .destructive) {
                    Task { await block() }
                }
            }
            .alert("moderation.block.failed", isPresented: $showsBlockError) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(verbatim: blockError ?? "")
            }
        }
    }

    private func block() async {
        guard let author, let backend = session.backend else { return }
        do {
            try await backend.block(author.id)
            onBlocked?()
        } catch {
            blockError = error.localizedDescription
            showsBlockError = true
        }
    }
}

// MARK: - Жалоба

/// «Пожаловаться»: причина, комментарий, отправка. Жалобы разбирает редакция.
struct ReportView: View {
    let target: ReportTarget
    let targetID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var reason: ReportReason?
    @State private var note = ""
    @State private var isSending = false
    @State private var isSent = false
    @State private var sendError: String?

    var body: some View {
        if isSent {
            NavigationStack {
                EmptyState(
                    icon: "checkmark.circle.fill",
                    title: String(localized: "moderation.report.sent"),
                    description: String(localized: "moderation.report.sentDetail")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("moderation.report")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.done") { dismiss() }
                    }
                }
            }
        } else {
            EditSheetContainer(
                title: String(localized: "moderation.report"),
                saveTitle: String(localized: "moderation.report.send"),
                isSaveDisabled: reason == nil || note.count > 1000,
                isSaving: isSending,
                wrapInForm: false,
                onSave: { Task { await send() } },
                onCancel: { dismiss() }
            ) {
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        FormSection(header: String(localized: "moderation.report.reason")) {
                            let options = ReportReason.options(for: target)
                            ForEach(options) { option in
                                CheckmarkRow(
                                    String(localized: String.LocalizationValue(option.titleKey)),
                                    isSelected: reason == option,
                                    config: .standard
                                ) {
                                    reason = option
                                }
                                if option.id != options.last?.id {
                                    Divider().padding(.leading, AppSpacing.lg)
                                }
                            }
                        }

                        FormSection(
                            header: String(localized: "moderation.report.note"),
                            footer: String(localized: "moderation.report.footer")
                        ) {
                            FormTextField(
                                text: $note,
                                placeholder: String(localized: "moderation.report.notePlaceholder"),
                                style: .rowMultiline(min: 2, max: 6)
                            )
                        }

                        if let sendError {
                            InlineStatusText(message: sendError, type: .error)
                        }
                    }
                    .screenPadding()
                    .padding(.vertical, AppSpacing.md)
                }
            }
        }
    }

    private func send() async {
        guard let reason, let backend = session.backend else { return }
        isSending = true
        defer { isSending = false }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await backend.report(target, id: targetID, reason: reason, note: trimmed.isEmpty ? nil : trimmed)
            isSent = true
        } catch {
            sendError = CommunityMessage.text(for: error)
        }
    }
}
