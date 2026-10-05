import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

extension Notification.Name {
    /// Своё место удалено — карте и спискам пора обновиться. `object` — id места.
    static let daladaPlaceDeleted = Notification.Name("dalada.placeDeleted")
}

/// «Изменить» и «Удалить» у своего улова: долгое нажатие и смахивание в списке. Правка — та же
/// форма улова, без фото (фото улова здесь не меняется). После правки или удаления — `onChanged`.
struct OwnCatchActions: ViewModifier {
    let catchID: UUID
    let environment: AppEnvironment
    /// В `List` — ещё и смахивание влево.
    var inList = false
    let onChanged: @MainActor () -> Void

    @State private var editing: CatchDraft?
    @State private var confirmsDelete = false
    @State private var errorText: String?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                editButton
                deleteButton
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if inList {
                    deleteButton
                    editButton
                        .tint(AppColors.accent)
                }
            }
            .sheet(item: $editing) { draft in
                CatchFormView(draft: draft, allowsPhoto: false) { edited in
                    Task { await save(edited) }
                }
            }
            .confirmationDialog("catch.delete.confirm", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("catch.delete", role: .destructive) {
                    Task { await delete() }
                }
            }
            .alert(
                "own.error.title",
                isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
            ) {
                Button("common.ok") {}
            } message: {
                Text(verbatim: errorText ?? "")
            }
    }

    private var editButton: some View {
        Button("catch.edit", systemImage: "pencil") {
            Task { await startEditing() }
        }
    }

    private var deleteButton: some View {
        Button("catch.delete", systemImage: "trash", role: .destructive) {
            confirmsDelete = true
        }
    }

    private func startEditing() async {
        guard let backend = environment.backend else {
            errorText = String(localized: "own.error.offline")
            return
        }
        do {
            guard let draft = try await backend.ownCatch(catchID) else {
                onChanged()
                return
            }
            editing = draft
        } catch {
            errorText = String(localized: "own.error.offline")
        }
    }

    private func save(_ draft: CatchDraft) async {
        guard let backend = environment.backend else { return }
        do {
            try await backend.updateCatch(draft)
            onChanged()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func delete() async {
        guard let backend = environment.backend else {
            errorText = String(localized: "own.error.offline")
            return
        }
        do {
            try await backend.deleteCatch(catchID)
            onChanged()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

extension View {
    func ownCatchActions(
        catchID: UUID,
        environment: AppEnvironment,
        inList: Bool = false,
        onChanged: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(OwnCatchActions(catchID: catchID, environment: environment, inList: inList, onChanged: onChanged))
    }
}
