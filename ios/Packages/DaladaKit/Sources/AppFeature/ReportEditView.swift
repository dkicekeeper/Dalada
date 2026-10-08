import Backend
import DaladaCore
import DesignComponents
import DesignSupport
import DesignTokens
import SwiftUI

/// Правка своего отчёта: как было на месте, заметка, кто видит. Уловы — своим меню в профиле,
/// место, время и фото не меняются.
struct ReportEditView: View {
    let placeName: String
    let environment: AppEnvironment
    let onSaved: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edit: ReportEdit
    @State private var isSaving = false
    @State private var saveError: String?

    init(edit: ReportEdit, placeName: String, environment: AppEnvironment, onSaved: @escaping @MainActor () -> Void) {
        self.placeName = placeName
        self.environment = environment
        self.onSaved = onSaved
        _edit = State(initialValue: edit)
    }

    var body: some View {
        EditSheetContainer(
            title: placeName,
            isSaveDisabled: edit.note.count > 2000,
            isSaving: isSaving,
            wrapInForm: false,
            onSave: { Task { await save() } },
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    FormSection(header: String(localized: "checkin.form.conditions")) {
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            FormChipRow(String(localized: "conditions.bite"), options: CheckinConditions.Bite.allCases, selection: $edit.conditions.bite) { $0.title }
                            FormChipRow(String(localized: "conditions.crowd"), options: CheckinConditions.Crowd.allCases, selection: $edit.conditions.crowd) { $0.title }
                            FormChipRow(String(localized: "conditions.water"), options: CheckinConditions.Water.allCases, selection: $edit.conditions.water) { $0.title }
                            FormChipRow(String(localized: "conditions.road"), options: CheckinConditions.Road.allCases, selection: $edit.conditions.road) { $0.title }
                        }
                        .padding(.vertical, AppSpacing.md)
                    }

                    FormSection(header: String(localized: "checkin.form.note")) {
                        FormTextField(
                            text: $edit.note,
                            placeholder: String(localized: "checkin.form.notePlaceholder"),
                            style: .rowMultiline(min: 2, max: 6)
                        )
                    }

                    FormSection(header: String(localized: "place.form.visibility")) {
                        SegmentedPicker(
                            title: String(localized: "place.form.visibility"),
                            selection: $edit.visibility,
                            options: DaladaCore.Visibility.allCases.map {
                                (label: String(localized: String.LocalizationValue($0.titleKey)), value: $0)
                            }
                        )
                        .padding(AppSpacing.md)
                    }

                    if let saveError {
                        InlineStatusText(message: saveError, type: .error)
                    }
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
            }
        }
    }

    private func save() async {
        guard let backend = environment.backend else {
            saveError = String(localized: "own.error.offline")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await backend.updateReport(edit)
            HapticManager.play(.confirm)
            onSaved()
            dismiss()
        } catch {
            saveError = error.localizedDescription
            HapticManager.play(.fail)
        }
    }
}
