import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

extension Notification.Name {
    /// Свою поездку изменили или удалили — спискам поездок пора обновиться. `object` — id поездки.
    static let daladaTripChanged = Notification.Name("dalada.tripChanged")
}

/// Правка своей поездки: название, вид отдыха, заметка. Трек и цифры не меняются.
struct TripEditView: View {
    let trip: TripDetails
    let environment: AppEnvironment
    let onSaved: @MainActor (TripDetails) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var activity: TripActivity
    @State private var note: String
    @State private var isSaving = false
    @State private var saveError: String?

    init(trip: TripDetails, environment: AppEnvironment, onSaved: @escaping @MainActor (TripDetails) -> Void) {
        self.trip = trip
        self.environment = environment
        self.onSaved = onSaved
        _title = State(initialValue: trip.summary.title)
        _activity = State(initialValue: trip.summary.activity)
        _note = State(initialValue: trip.summary.note ?? "")
    }

    var body: some View {
        EditSheetContainer(
            title: String(localized: "trip.edit.title"),
            isSaveDisabled: !isValid,
            isSaving: isSaving,
            wrapInForm: false,
            onSave: { Task { await save() } },
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    FormSection(header: String(localized: "trip.finish.name")) {
                        FormTextField(text: $title, placeholder: String(localized: "trip.finish.name"), style: .row)
                        Divider().padding(.leading, AppSpacing.lg)
                        MenuPickerRow(
                            title: String(localized: "trip.finish.activity"),
                            selection: $activity,
                            options: TripActivity.allCases.map {
                                (label: String(localized: String.LocalizationValue($0.titleKey)), value: $0)
                            }
                        )
                    }
                    FormSection(header: String(localized: "checkin.form.note")) {
                        FormTextField(
                            text: $note,
                            placeholder: String(localized: "trip.finish.notePlaceholder"),
                            style: .rowMultiline(min: 2, max: 6)
                        )
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

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        (1...100).contains(trimmedTitle.count) && note.count <= 2000
    }

    private func save() async {
        guard let backend = environment.backend else {
            saveError = String(localized: "own.error.offline")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await backend.updateTrip(trip.summary.id, title: trimmedTitle, activity: activity, note: note)
            onSaved(trip.with(title: trimmedTitle, activity: activity, note: note))
            NotificationCenter.default.post(name: .daladaTripChanged, object: trip.summary.id)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
