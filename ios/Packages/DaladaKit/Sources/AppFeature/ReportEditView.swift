import Backend
import DaladaCore
import DesignComponents
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
        NavigationStack {
            Form {
                Section {
                    ChipPicker(String(localized: "conditions.bite"), options: CheckinConditions.Bite.allCases, selection: $edit.conditions.bite) { $0.title }
                    ChipPicker(String(localized: "conditions.crowd"), options: CheckinConditions.Crowd.allCases, selection: $edit.conditions.crowd) { $0.title }
                    ChipPicker(String(localized: "conditions.water"), options: CheckinConditions.Water.allCases, selection: $edit.conditions.water) { $0.title }
                    ChipPicker(String(localized: "conditions.road"), options: CheckinConditions.Road.allCases, selection: $edit.conditions.road) { $0.title }
                } header: {
                    Text("checkin.form.conditions")
                }

                Section("checkin.form.note") {
                    TextField("checkin.form.notePlaceholder", text: $edit.note, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("place.form.visibility") {
                    Picker("place.form.visibility", selection: $edit.visibility) {
                        ForEach(DaladaCore.Visibility.allCases) { visibility in
                            Text(LocalizedStringKey(visibility.titleKey)).tag(visibility)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(AppColors.destructive)
                    }
                }
            }
            .navigationTitle(Text(verbatim: placeName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("common.save") {
                            Task { await save() }
                        }
                        .disabled(edit.note.count > 2000)
                    }
                }
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
            onSaved()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
